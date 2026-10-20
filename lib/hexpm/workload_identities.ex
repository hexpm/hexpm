defmodule Hexpm.WorkloadIdentities do
  @moduledoc """
  Context for configuring workload identities and minting short-lived tokens.

  A package's workload identities publish that package. An organization's workload identities
  fetch from the organization's repository, and those with the `write` role
  also publish and create packages in it. A `write` workload identity with public
  coverage publishes the public packages its organization owns. It doesn't create
  public packages, whose first release is published with an account or a key.
  """

  use Hexpm.Context

  alias Hexpm.FeatureFlags
  alias Hexpm.OAuth.{JWT, Token}
  alias Hexpm.Repository.{Package, Repositories, Repository}
  alias Hexpm.WorkloadIdentities.{OIDC, Provider, WorkloadIdentity, VerifiedToken}

  @mint_expires_in 15 * 60

  # An organization workload identity publishes a public package its
  # organization owns at the level an organization key needs to publish it.
  @public_owner_level "maintainer"

  @doc """
  Whether workload identities are on for anyone, which shows the docs and
  accepts OIDC tokens at all.
  """
  def available?, do: FeatureFlags.available?(:workload_identity)

  @doc """
  Whether an organization or a package may configure and use workload
  identities, see `Hexpm.FeatureFlags.enabled?/2`.
  """
  def enabled?(owner), do: FeatureFlags.enabled?(:workload_identity, owner)

  def audience, do: OIDC.audience()

  def list(%Package{} = package) do
    from(tp in WorkloadIdentity, where: tp.package_id == ^package.id, order_by: [asc: tp.id])
    |> Repo.all()
  end

  def list(%Organization{} = organization) do
    from(tp in WorkloadIdentity,
      where: tp.organization_id == ^organization.id,
      order_by: [asc: tp.id]
    )
    |> Repo.all()
  end

  @doc """
  Lists the organization workload identities that publish the package, with
  their organizations. For a package in an organization's repository, those
  are the organization's `write` workload identities whose private package
  list covers it. For a public package, those are the `write` workload
  identities with public coverage of the organizations that own it, leaving
  out organizations that don't have workload identities enabled.
  """
  def list_covering(%Package{repository_id: 1} = package) do
    package
    |> public_identities_query()
    |> Repo.all()
    |> Repo.preload(:organization)
    |> Enum.filter(&enabled?(&1.organization))
  end

  def list_covering(%Package{repository: %Repository{} = repository, name: name}) do
    repository
    |> organization_identities_query(["write"], name)
    |> Repo.all()
    |> Repo.preload(:organization)
  end

  @doc """
  Whether an organization workload identity publishes a public package now,
  which needs its organization to own the package at the level an
  organization key needs to publish it.
  """
  def publishes_public?(
        %WorkloadIdentity{organization_id: organization_id} = workload_identity,
        %Package{repository_id: 1} = package
      )
      when not is_nil(organization_id) do
    WorkloadIdentity.covers_public_package?(workload_identity, package.name) and
      Repo.exists?(
        from(po in owners_query(package),
          join: u in assoc(po, :user),
          where: u.organization_id == ^organization_id
        )
      )
  end

  def publishes_public?(_workload_identity, _package), do: false

  @doc """
  The public packages an organization workload identity publishes now.
  """
  def covered_public_packages(%WorkloadIdentity{covers_public: true} = workload_identity) do
    query =
      from(p in Package,
        join: po in assoc(p, :package_owners),
        join: u in assoc(po, :user),
        where: p.repository_id == 1,
        where: u.organization_id == ^workload_identity.organization_id,
        where: po.level in ^PackageOwner.level_or_higher(@public_owner_level),
        order_by: p.name
      )

    query =
      if names = workload_identity.public_packages,
        do: from(p in query, where: p.name in ^names),
        else: query

    Repo.all(query)
  end

  def covered_public_packages(%WorkloadIdentity{}), do: []

  @doc """
  The public packages an organization workload identity lists that its
  organization doesn't own at the level it needs, so it doesn't publish them.
  """
  def unowned_public_packages(
        %WorkloadIdentity{covers_public: true, public_packages: names} = workload_identity
      )
      when is_list(names) do
    names -- Enum.map(covered_public_packages(workload_identity), & &1.name)
  end

  def unowned_public_packages(%WorkloadIdentity{}), do: []

  def get(%Package{} = package, id) do
    case parse_id(id) do
      {:ok, id} -> Repo.get_by(WorkloadIdentity, id: id, package_id: package.id)
      :error -> nil
    end
  end

  def get(%Organization{} = organization, id) do
    case parse_id(id) do
      {:ok, id} -> Repo.get_by(WorkloadIdentity, id: id, organization_id: organization.id)
      :error -> nil
    end
  end

  def get(id) do
    case parse_id(id) do
      {:ok, id} -> Repo.get(WorkloadIdentity, id)
      :error -> nil
    end
  end

  @doc """
  Adds a workload identity to a package or to an organization.

  `:before_lookup` runs once the params are valid, right before Hex asks GitHub
  for the owner and repository IDs. It gets the most GitHub calls the lookup
  can make, and refuses the add when it returns `{:error, reason}`.
  """
  def create(owner, params, opts)

  # The hexpm organization owns the public repository, which organization
  # workload identities never cover.
  def create(%Organization{id: 1}, _params, _opts), do: {:error, :not_allowed}

  # A package in an organization's repository is published by the organization's
  # workload identities, which only admins manage and every admin hears about.
  def create(%Package{repository_id: repository_id}, _params, _opts) when repository_id != 1,
    do: {:error, :not_allowed}

  def create(owner, params, opts) do
    audit_data = Keyword.fetch!(opts, :audit)
    before_lookup = Keyword.get(opts, :before_lookup, fn _calls -> :ok end)
    provider_name = params["provider"] || params[:provider]

    with {:ok, provider} <- fetch_provider(provider_name) do
      params = params |> normalize_params() |> Map.put("provider", provider.name())

      changeset =
        %WorkloadIdentity{}
        |> WorkloadIdentity.changeset(params, owner)
        |> check_public_owner(owner, [])
        |> check_duplicate(owner)

      with {:ok, changeset} <- resolve_ids(changeset, provider, before_lookup) do
        insert_identity(owner, changeset, audit_data)
      end
    end
  end

  @doc """
  Changes a workload identity, see `WorkloadIdentity.update_changeset/2`.

  Tokens are checked against the packages a workload identity covers when
  they're used, but not against the workflow they were issued to. So a change
  that drops a repository or changes the workflow or the environment revokes
  the tokens the workload identity issued.

  Hex only asks GitHub about the repositories a change adds, since the others
  keep their pinned IDs. A change that removes the environment of a workload
  identity that publishes looks all of them up, to know whether one is public.

  `"version"` in the params is the `version/1` the edit form was loaded with.
  The change returns `{:error, :changed}` when the workload identity changed
  since then, or since `workload_identity` was read when there's no version.

  `:before_lookup` works as for `create/3`.
  """
  def update(%WorkloadIdentity{} = workload_identity, params, opts) do
    audit_data = Keyword.fetch!(opts, :audit)
    before_lookup = Keyword.get(opts, :before_lookup, fn _calls -> :ok end)
    workload_identity = preload_owner(workload_identity)
    owner = workload_identity.organization || workload_identity.package
    params = normalize_params(params)
    expected_version = params["version"] || version(workload_identity)

    with {:ok, provider} <- fetch_provider(workload_identity.provider),
         true <- expected_version == version(workload_identity) || {:error, :changed} do
      changeset =
        workload_identity
        |> WorkloadIdentity.update_changeset(params)
        |> check_public_owner(owner, workload_identity.public_packages || [])
        |> check_duplicate(owner)

      with {:ok, changeset} <- resolve_ids(changeset, provider, before_lookup) do
        if identity_changed?(workload_identity, changeset),
          do: update_identity(owner, workload_identity, changeset, expected_version, audit_data),
          else: {:ok, workload_identity}
      end
    end
  end

  @changeable_fields [
    :workflow,
    :environment,
    :covers_private,
    :packages,
    :covers_public,
    :public_packages
  ]

  defp identity_changed?(workload_identity, changeset),
    do:
      configuration_snapshot(workload_identity) !=
        configuration_snapshot(Ecto.Changeset.apply_changes(changeset))

  defp configuration_snapshot(workload_identity),
    do: {Map.take(workload_identity, @changeable_fields), repository_set(workload_identity)}

  @doc """
  The version of a workload identity's configuration, which an edit form
  carries so a save refuses to overwrite a change made since it was loaded.
  """
  def version(%WorkloadIdentity{} = workload_identity) do
    snapshot = :erlang.term_to_binary(configuration_snapshot(workload_identity), [:deterministic])
    Base.url_encode64(:crypto.hash(:sha256, snapshot), padding: false)
  end

  # Hex asks GitHub for the IDs once everything else is valid.
  defp resolve_ids(changeset, provider, before_lookup) do
    action = if changeset.data.id, do: :update, else: :insert

    if changeset.valid? do
      names = names_to_resolve(changeset)

      with :ok <- before_lookup.(github_calls(changeset, names)),
           {:ok, immutable_ids} <- resolve(changeset, provider, names) do
        changeset = WorkloadIdentity.put_immutable_ids(changeset, immutable_ids)

        if changeset.valid?,
          do: {:ok, changeset},
          else: {:error, %{changeset | action: action}}
      end
    else
      {:error, %{changeset | action: action}}
    end
  end

  defp names_to_resolve(%Ecto.Changeset{data: %WorkloadIdentity{id: nil}} = changeset),
    do: Enum.map(Ecto.Changeset.get_field(changeset, :repositories), & &1.name)

  defp names_to_resolve(changeset) do
    names = Enum.map(Ecto.Changeset.get_field(changeset, :repositories), & &1.name)

    if removes_environment?(changeset) do
      names
    else
      names -- Enum.map(changeset.data.repositories, & &1.name)
    end
  end

  defp removes_environment?(changeset) do
    Ecto.Changeset.get_field(changeset, :role) == "write" and
      Ecto.Changeset.get_field(changeset, :environment) in [nil, ""] and
      changeset.data.environment not in [nil, ""]
  end

  # One call per repository, and on an add one more for the owner's profile
  # when Hex sees none of them. A change uses the owner's pinned ID instead.
  defp github_calls(%Ecto.Changeset{data: %WorkloadIdentity{id: nil}}, names),
    do: length(names) + 1

  defp github_calls(_changeset, names), do: length(names)

  defp resolve(%Ecto.Changeset{data: %WorkloadIdentity{id: id} = data}, _provider, [])
       when not is_nil(id),
       do: {:ok, %{repository_owner_id: data.repository_owner_id, repositories: %{}}}

  defp resolve(changeset, provider, names) do
    provider.resolve_immutable_ids(%{
      repository_owner: Ecto.Changeset.get_field(changeset, :repository_owner),
      repository_owner_id: changeset.data.repository_owner_id,
      repositories: names
    })
  end

  # Only public packages the organization owns can be listed. Ownership is
  # checked again at every exchange and publish, so this only tells the admin
  # about a name they can't use. A change only checks the names it adds, so a
  # package the organization stopped owning doesn't block it.
  defp check_public_owner(changeset, %Organization{} = organization, listed) do
    names = Ecto.Changeset.get_field(changeset, :public_packages)

    if is_list(names) and not Keyword.has_key?(changeset.errors, :public_packages) do
      added = names -- listed

      owned =
        from(p in Package,
          join: po in assoc(p, :package_owners),
          join: u in assoc(po, :user),
          where: p.repository_id == 1 and p.name in ^added,
          where: u.organization_id == ^organization.id,
          where: po.level in ^PackageOwner.level_or_higher(@public_owner_level),
          select: p.name
        )
        |> Repo.all()

      WorkloadIdentity.validate_public_owner(changeset, added -- owned)
    else
      changeset
    end
  end

  defp check_public_owner(changeset, %Package{}, _listed), do: changeset

  # Another workload identity of the same package or organization with the
  # same repositories, workflow and environment would match the same tokens.
  defp check_duplicate(%Ecto.Changeset{valid?: false} = changeset, _owner), do: changeset

  defp check_duplicate(changeset, owner) do
    configuration = configuration(Ecto.Changeset.apply_changes(changeset))

    duplicate? =
      owner
      |> list()
      |> Enum.any?(&(&1.id != changeset.data.id and configuration(&1) == configuration))

    if duplicate?,
      do:
        Ecto.Changeset.add_error(
          changeset,
          :repositories,
          "already have a workload identity with this workflow and environment"
        ),
      else: changeset
  end

  defp configuration(workload_identity) do
    {
      workload_identity.repository_owner,
      MapSet.new(workload_identity.repositories, & &1.name),
      workload_identity.workflow || "",
      String.downcase(workload_identity.environment || "")
    }
  end

  defp insert_identity(owner, changeset, audit_data) do
    action = audit_action(owner, :add)

    multi =
      Multi.new()
      |> check_owner(owner, audit_data)
      |> Multi.insert(:workload_identity, changeset)
      |> audit(audit_data, action, fn %{workload_identity: tp} -> preload_owner(tp) end)

    case Repo.transaction(multi) do
      {:ok, %{workload_identity: workload_identity}} ->
        workload_identity = preload_owner(workload_identity)
        notify(:added, workload_identity, audit_data)
        {:ok, workload_identity}

      {:error, _op, changeset, _} ->
        {:error, changeset}
    end
  end

  defp update_identity(owner, previous, changeset, expected_version, audit_data) do
    action = audit_action(owner, :update)

    multi =
      Multi.new()
      |> check_owner(owner, audit_data)
      |> Multi.run(:current, fn repo, _changes ->
        lock_unchanged(repo, previous, expected_version)
      end)
      |> Multi.update(:workload_identity, changeset)
      |> Multi.run(:tokens, fn repo, %{workload_identity: updated} ->
        if revokes_tokens?(previous, updated) do
          {count, _} = repo.update_all(revoke_tokens_query([updated.id]), [])
          {:ok, count}
        else
          {:ok, 0}
        end
      end)
      |> audit(audit_data, action, fn %{workload_identity: updated} ->
        {previous, preload_owner(updated)}
      end)

    case Repo.transaction(multi) do
      {:ok, %{workload_identity: updated}} ->
        updated = preload_owner(updated)
        notify_change(previous, updated, audit_data)
        {:ok, updated}

      {:error, :current, reason, _} ->
        {:error, reason}

      {:error, _op, changeset, _} ->
        {:error, changeset}
    end
  end

  # The change was made to the workload identity as the edit form showed it.
  # Locking its row, and refusing when it changed since, keeps another change
  # from being overwritten unseen, and keeps the tokens to revoke, the audit
  # entry and the emails based on what it was. The lock doesn't block the key
  # share lock a release insert takes on the row.
  defp lock_unchanged(repo, previous, expected_version) do
    current =
      repo.one(
        from(wi in WorkloadIdentity, where: wi.id == ^previous.id, lock: "FOR NO KEY UPDATE")
      )

    cond do
      is_nil(current) -> {:error, :not_found}
      version(current) != expected_version -> {:error, :changed}
      true -> {:ok, current}
    end
  end

  defp revokes_tokens?(previous, updated) do
    previous.workflow != updated.workflow or
      String.downcase(previous.environment || "") != String.downcase(updated.environment || "") or
      not keeps_repositories?(previous.repositories, updated.repositories)
  end

  # No repositories match every repository of the owner.
  defp keeps_repositories?(_previous, []), do: true
  defp keeps_repositories?([], _updated), do: false

  defp keeps_repositories?(previous, updated) do
    MapSet.subset?(
      MapSet.new(previous, &{&1.name, &1.id}),
      MapSet.new(updated, &{&1.name, &1.id})
    )
  end

  # Ownership was checked before Hex asked GitHub. A transfer in the meantime
  # removed the package's workload identities, so check again under the package row lock
  # that owner changes take.
  defp check_owner(multi, %Package{} = package, %{user: user}) do
    Multi.run(multi, :owner, fn repo, _changes ->
      repo.one!(from(p in Package, where: p.id == ^package.id, lock: "FOR NO KEY UPDATE"))
      package = repo.preload(package, :repository)

      if Packages.owner_with_access?(package, user, "full"),
        do: {:ok, user},
        else: {:error, :not_owner}
    end)
  end

  defp check_owner(multi, %Organization{}, _audit_data), do: multi

  # Takes the locks in the same order as a change and an owner transfer: the
  # package's row, then the workload identity's, then its tokens'. The removal,
  # its audit entry and its emails use the locked row, so they show any change
  # that committed first.
  def delete(%WorkloadIdentity{} = workload_identity, audit: audit_data) do
    workload_identity = preload_owner(workload_identity)
    owner = workload_identity.organization || workload_identity.package
    action = audit_action(owner, :remove)

    multi =
      Multi.new()
      |> lock_package(owner)
      |> Multi.run(:current, fn repo, _changes ->
        query =
          from(wi in WorkloadIdentity, where: wi.id == ^workload_identity.id, lock: "FOR UPDATE")

        case repo.one(query) do
          nil ->
            {:error, :not_found}

          current ->
            {:ok,
             %{
               current
               | package: workload_identity.package,
                 organization: workload_identity.organization
             }}
        end
      end)
      |> Multi.update_all(:tokens, revoke_tokens_query([workload_identity.id]), [])
      |> Multi.delete(:workload_identity, & &1.current)
      |> audit(audit_data, action, & &1.current)

    case Repo.transaction(multi) do
      {:ok, %{current: current, workload_identity: deleted}} ->
        notify(:removed, current, audit_data)
        {:ok, deleted}

      {:error, :current, reason, _} ->
        {:error, reason}

      {:error, _op, changeset, _} ->
        {:error, changeset}
    end
  end

  defp lock_package(multi, %Package{} = package) do
    Multi.run(multi, :package_lock, fn repo, _changes ->
      repo.one!(from(p in Package, where: p.id == ^package.id, lock: "FOR NO KEY UPDATE"))
      {:ok, :locked}
    end)
  end

  defp lock_package(multi, %Organization{}), do: multi

  @doc """
  Revokes the tokens issued to the given workload identities. Their rows outlive the
  workload identities, like any other OAuth token's, until the purge archives and deletes
  them after they expire. A row is also what keeps its OIDC token from being
  exchanged again.

  Returns the query, suitable for use in Multi.update_all.
  """
  def revoke_tokens_query(workload_identity_ids) do
    now = DateTime.utc_now()

    from(t in Token,
      where: t.workload_identity_id in ^workload_identity_ids and is_nil(t.revoked_at),
      update: [set: [revoked_at: ^now, updated_at: ^now]]
    )
  end

  defp audit_action(%Organization{}, :add), do: "organization.workload_identity.add"
  defp audit_action(%Organization{}, :update), do: "organization.workload_identity.update"
  defp audit_action(%Organization{}, :remove), do: "organization.workload_identity.remove"
  defp audit_action(%Package{}, :add), do: "workload_identity.create"
  defp audit_action(%Package{}, :update), do: "workload_identity.update"
  defp audit_action(%Package{}, :remove), do: "workload_identity.remove"

  defp preload_owner(%WorkloadIdentity{} = workload_identity) do
    Repo.preload(workload_identity, [:organization, package: :repository])
  end

  # Not an optional email: a workload identity grants publish rights to whoever can run
  # the workflow, so every owner, or every organization admin, hears about it.
  defp notify(event, %WorkloadIdentity{organization: %Organization{} = organization} = tp, audit) do
    organization = %{
      organization
      | organization_users: Organizations.all_members(organization, user: :emails)
    }

    email =
      case event do
        :added -> Emails.organization_workload_identity_added(tp, organization, audit.user)
        :removed -> Emails.organization_workload_identity_removed(tp, organization, audit.user)
      end

    if email.to != [] do
      Mailer.deliver!(email)
    end

    notify_public_owners(event, tp, organization, email.to, audit.user)
  end

  defp notify(event, %WorkloadIdentity{package: package} = workload_identity, audit_data) do
    owners =
      package
      |> Owners.all(user: [:emails, organization: [organization_users: [user: :emails]]])
      |> Enum.map(& &1.user)

    if owners != [] do
      case event do
        :added -> Emails.workload_identity_added(workload_identity, owners, audit_data.user)
        :removed -> Emails.workload_identity_removed(workload_identity, owners, audit_data.user)
      end
      |> Mailer.deliver!()
    end
  end

  defp notify_change(
         previous,
         %WorkloadIdentity{organization: %Organization{} = organization} = updated,
         audit_data
       ) do
    organization = %{
      organization
      | organization_users: Organizations.all_members(organization, user: :emails)
    }

    email =
      Emails.organization_workload_identity_changed(
        previous,
        updated,
        organization,
        audit_data.user
      )

    if email.to != [] do
      Mailer.deliver!(email)
    end

    notify_public_owners_of_change(previous, updated, organization, email.to, audit_data.user)
  end

  defp notify_change(previous, %WorkloadIdentity{package: package} = updated, audit_data) do
    owners =
      package
      |> Owners.all(user: [:emails, organization: [organization_users: [user: :emails]]])
      |> Enum.map(& &1.user)

    if owners != [] do
      previous
      |> Emails.workload_identity_changed(updated, owners, audit_data.user)
      |> Mailer.deliver!()
    end
  end

  # The other owners of the public packages an organization workload identity
  # publishes hear about it the same way as about a package's own workload
  # identity. Everyone the organization's email already reached is left out,
  # and everyone else gets one email that names their packages.
  defp notify_public_owners(event, workload_identity, organization, notified, actor) do
    workload_identity
    |> covered_public_packages()
    |> Enum.map(&{&1, event})
    |> each_public_owner(organization, notified, fn user, packages ->
      names = Map.fetch!(packages, event)

      case event do
        :added ->
          Emails.public_workload_identity_added(
            workload_identity,
            organization,
            user,
            names,
            actor
          )

        :removed ->
          Emails.public_workload_identity_removed(
            workload_identity,
            organization,
            user,
            names,
            actor
          )
      end
      |> Mailer.deliver!()
    end)
  end

  # A change tells the owners of the packages it starts or stops publishing,
  # and, when it changes which workflows the workload identity trusts, the
  # owners of the packages it keeps publishing.
  defp notify_public_owners_of_change(previous, updated, organization, notified, actor) do
    before = covered_public_packages(previous)
    now = covered_public_packages(updated)
    before_names = MapSet.new(before, & &1.name)
    now_names = MapSet.new(now, & &1.name)
    trust_changed? = trust_changed?(previous, updated)

    started_or_kept =
      Enum.flat_map(now, fn package ->
        cond do
          not MapSet.member?(before_names, package.name) -> [{package, :started}]
          trust_changed? -> [{package, :kept}]
          true -> []
        end
      end)

    stopped = for package <- before, package.name not in now_names, do: {package, :stopped}

    each_public_owner(started_or_kept ++ stopped, organization, notified, fn user, packages ->
      previous
      |> Emails.public_workload_identity_changed(updated, organization, user, packages, actor)
      |> Mailer.deliver!()
    end)
  end

  defp trust_changed?(previous, updated) do
    previous.workflow != updated.workflow or
      String.downcase(previous.environment || "") != String.downcase(updated.environment || "") or
      repository_set(previous) != repository_set(updated)
  end

  defp repository_set(workload_identity),
    do: MapSet.new(workload_identity.repositories, &{&1.name, &1.id})

  # Calls `fun` once for each person who owns some of the packages, other than
  # through the organization or as one of `notified`, with their package names
  # grouped by tag.
  defp each_public_owner(tagged_packages, organization, notified, fun) do
    notified = MapSet.new(notified, &recipient_address/1)

    tagged_packages
    |> Enum.flat_map(fn {package, tag} ->
      package
      |> Owners.all(user: [:emails, organization: [organization_users: [user: :emails]]])
      |> Enum.reject(&(&1.user.organization_id == organization.id))
      |> Enum.flat_map(&people(&1.user))
      |> Enum.map(&{&1, tag, package.name})
    end)
    |> Enum.reject(fn {user, _tag, _name} ->
      address = User.email(user, :primary)
      is_nil(address) or MapSet.member?(notified, address)
    end)
    |> Enum.group_by(fn {user, _tag, _name} -> user.id end)
    |> Enum.sort_by(fn {user_id, _entries} -> user_id end)
    |> Enum.each(fn {_user_id, [{user, _tag, _name} | _] = entries} ->
      packages =
        entries
        |> Enum.group_by(&elem(&1, 1), &elem(&1, 2))
        |> Map.new(fn {tag, names} -> {tag, names |> Enum.uniq() |> Enum.sort()} end)

      fun.(user, packages)
    end)
  end

  defp recipient_address({_name, address}), do: address
  defp recipient_address(address), do: address

  # An organization that owns a package is reached through its admins, or
  # every member when it has no admin, the same as `Hexpm.Emails` reaches it.
  defp people(%User{organization: %Organization{organization_users: organization_users}}) do
    admins = Enum.filter(organization_users, &(&1.role == "admin"))
    members = if admins == [], do: organization_users, else: admins
    Enum.map(members, & &1.user)
  end

  defp people(%User{} = user), do: [user]

  @doc """
  Verifies an OIDC token and mints a short-lived Hex access token, see `mint/2`.
  """
  def verify_and_mint(oidc_token, opts) do
    with {:ok, verified} <- verify(oidc_token) do
      mint(verified, opts)
    end
  end

  @doc """
  Verifies an OIDC token's signature and standard claims against its issuer.
  """
  def verify(oidc_token) when is_binary(oidc_token) do
    with :ok <- enabled_guard(),
         {:ok, peeked} <- OIDC.peek_claims(oidc_token),
         {:ok, issuer} <- fetch_issuer(peeked),
         {:ok, provider} <- fetch_provider_by_issuer(issuer),
         {:ok, claims} <- OIDC.verify(oidc_token, issuer) do
      {:ok, %VerifiedToken{provider: provider, claims: claims}}
    end
    |> tap_failure()
  end

  def verify(_), do: {:error, :invalid_token}

  @doc """
  Mints a short-lived Hex access token for a verified OIDC token.

  With `:package`, the token is scoped to that package in `:repository`
  (default `"hexpm"`). A package in the public repository matches its own
  workload identities and the `write` workload identities with public coverage
  of the organizations that own it, and has to exist. A package in an
  organization's repository matches the organization's `write` workload
  identities that cover the name, and doesn't have to exist, because an
  organization workload identity can create it.

  An identity whose owner doesn't have workload identities enabled doesn't
  match, so it can't hide a later identity that does.

  Without `:package`, the token is scoped to the organization repository named
  by `:repository`, and any of the organization's workload identities can match.
  """
  def mint(%VerifiedToken{provider: provider, claims: claims}, opts) do
    with :ok <- provider.validate_claims(claims),
         :ok <- check_unused(claims),
         {:ok, repository} <- fetch_repository(opts),
         {:ok, workload_identity, scope} <- find_identity(repository, provider, claims, opts),
         :ok <- check_billing(repository),
         {:ok, token} <- mint_token(workload_identity, scope, claims, provider) do
      :telemetry.execute([:hexpm, :workload_identity, :mint, :success], %{count: 1}, %{
        provider: provider.name(),
        package_id: workload_identity.package_id,
        organization_id: workload_identity.organization_id
      })

      {:ok, token}
    end
    |> tap_failure()
  end

  def rate_limit_key(%VerifiedToken{provider: provider, claims: claims}),
    do: provider.rate_limit_key(claims)

  defp tap_failure({:error, reason} = error) do
    emit_failure(reason)
    error
  end

  defp tap_failure(result), do: result

  defp enabled_guard do
    if available?(), do: :ok, else: {:error, :disabled}
  end

  defp fetch_issuer(%{"iss" => issuer}) when is_binary(issuer) and issuer != "" do
    {:ok, issuer}
  end

  defp fetch_issuer(_), do: {:error, :issuer_missing}

  defp emit_failure(%Ecto.Changeset{}), do: emit_failure(:changeset_error)

  defp emit_failure(reason) when is_atom(reason) do
    :telemetry.execute([:hexpm, :workload_identity, :mint, :failure], %{count: 1}, %{
      reason: reason
    })
  end

  defp emit_failure(_reason), do: emit_failure(:request_failed)

  defp fetch_provider(nil), do: {:error, :unknown_provider}

  defp fetch_provider(name) do
    case Provider.get(name) do
      nil -> {:error, :unknown_provider}
      provider -> {:ok, provider}
    end
  end

  defp fetch_provider_by_issuer(issuer) do
    case Provider.get_by_issuer(issuer) do
      nil -> {:error, :issuer_not_allowed}
      provider -> {:ok, provider}
    end
  end

  defp normalize_params(params), do: Map.new(params, fn {k, v} -> {to_string(k), v} end)

  # Inserting the token is what makes an OIDC token single-use. Checking first
  # answers a used token the same way whatever scope it asks for.
  defp check_unused(claims) do
    query =
      from(t in Token,
        where: t.grant_type == "workload_identity" and t.grant_reference == ^claims["jti"]
      )

    if Repo.exists?(query), do: {:error, :token_replayed}, else: :ok
  end

  defp fetch_repository(opts) do
    name =
      if Keyword.has_key?(opts, :package),
        do: Keyword.get(opts, :repository, "hexpm"),
        else: Keyword.fetch!(opts, :repository)

    case Repositories.get(name, [:organization]) do
      nil -> {:error, :repository_not_found}
      repository -> {:ok, repository}
    end
  end

  defp find_identity(repository, provider, claims, opts) do
    case Keyword.fetch(opts, :package) do
      {:ok, package_name} -> find_package_identity(repository, package_name, provider, claims)
      :error -> find_repository_identity(repository, provider, claims)
    end
  end

  defp find_package_identity(repository, package_name, provider, claims) do
    package = Packages.get(repository, package_name)

    workload_identities =
      repository
      |> package_identities_queries(package, package_name)
      |> Enum.flat_map(&(&1 |> for_provider(provider) |> Repo.all()))
      |> with_owners(repository, package)

    case find_match(workload_identities, provider, claims) do
      {:ok, workload_identity} ->
        with :ok <- check_package_name(package, package_name) do
          {:ok, workload_identity, "package:#{repository.name}/#{package_name}"}
        end

      {:error, :no_matching_identity} ->
        if is_nil(package) and workload_identities == [],
          do: {:error, :package_not_found},
          else: {:error, :no_matching_identity}

      {:error, :disabled} = error ->
        error
    end
  end

  # The first matching identity whose owner has workload identities enabled.
  # One that matches but isn't enabled says so only when no other one is.
  defp find_match(workload_identities, provider, claims) do
    matching = Enum.filter(workload_identities, &provider.match?(&1, claims))

    cond do
      workload_identity = Enum.find(matching, &enabled?(owner(&1))) ->
        {:ok, workload_identity}

      matching != [] ->
        {:error, :disabled}

      true ->
        {:error, :no_matching_identity}
    end
  end

  defp owner(%WorkloadIdentity{package_id: nil, organization: organization}), do: organization
  defp owner(%WorkloadIdentity{package: package}), do: package

  # Checked after a match, so a workflow that matches nothing learns nothing
  # about which organizations or packages exist. Some existing packages predate
  # the current name rules, so only a name that no package has yet must be one
  # a package can be created with.
  defp check_package_name(%Package{}, _package_name), do: :ok

  defp check_package_name(nil, package_name) do
    if WorkloadIdentity.valid_package_name?(package_name),
      do: :ok,
      else: {:error, :invalid_package_name}
  end

  defp package_identities_queries(%Repository{id: 1}, nil = _package, _package_name), do: []

  # A public package's own workload identities match before those of the
  # organizations that own it.
  defp package_identities_queries(%Repository{id: 1}, %Package{} = package, _package_name) do
    [
      from(tp in WorkloadIdentity, where: tp.package_id == ^package.id, order_by: [asc: tp.id]),
      public_identities_query(package)
    ]
  end

  defp package_identities_queries(%Repository{} = repository, _package, package_name) do
    [organization_identities_query(repository, ["write"], package_name)]
  end

  # Ownership is read when the query runs, so an organization that stops
  # owning the package stops publishing it at once.
  defp public_identities_query(%Package{} = package) do
    organization_ids =
      from(po in owners_query(package),
        join: u in assoc(po, :user),
        where: not is_nil(u.organization_id),
        select: u.organization_id
      )

    from(tp in WorkloadIdentity,
      where: tp.organization_id in subquery(organization_ids),
      where: tp.role == "write" and tp.covers_public,
      where: is_nil(tp.public_packages) or ^package.name in tp.public_packages,
      order_by: [asc: tp.id]
    )
  end

  defp owners_query(%Package{id: package_id}) do
    from(po in PackageOwner,
      where: po.package_id == ^package_id,
      where: po.level in ^PackageOwner.level_or_higher(@public_owner_level)
    )
  end

  defp find_repository_identity(%Repository{id: 1}, _provider, _claims) do
    {:error, :no_matching_identity}
  end

  defp find_repository_identity(repository, provider, claims) do
    workload_identities =
      repository
      |> organization_identities_query(WorkloadIdentity.roles(), nil)
      |> for_provider(provider)
      |> Repo.all()
      |> with_owners(repository, nil)

    with {:ok, workload_identity} <- find_match(workload_identities, provider, claims) do
      {:ok, workload_identity, "repository:#{repository.name}"}
    end
  end

  # A public package's own identities belong to the package, and an
  # organization's identity that publishes a public package belongs to its
  # organization. The others belong to the repository's organization.
  defp with_owners(workload_identities, %Repository{id: 1}, package) do
    workload_identities
    |> Repo.preload(:organization)
    |> Enum.map(&%{&1 | package: package})
  end

  defp with_owners(workload_identities, repository, _package),
    do: Enum.map(workload_identities, &%{&1 | organization: repository.organization})

  defp organization_identities_query(%Repository{id: 1}, _roles, _package_name) do
    from(tp in WorkloadIdentity, where: false)
  end

  defp organization_identities_query(%Repository{} = repository, roles, package_name) do
    query =
      from(tp in WorkloadIdentity,
        where: tp.organization_id == ^repository.organization_id and tp.role in ^roles,
        where: tp.covers_private,
        order_by: [asc: tp.id]
      )

    if package_name do
      from(tp in query, where: is_nil(tp.packages) or ^package_name in tp.packages)
    else
      query
    end
  end

  defp for_provider(query, provider) do
    from(tp in query, where: tp.provider == ^provider.name())
  end

  # Checked after a match, so a workflow that matches nothing learns nothing
  # about the organization's subscription.
  defp check_billing(%Repository{id: 1}), do: :ok

  defp check_billing(%Repository{organization: organization}) do
    if Organization.billing_active?(organization),
      do: :ok,
      else: {:error, :billing_inactive}
  end

  defp mint_token(workload_identity, scope, claims, provider) do
    expires_in = @mint_expires_in
    expires_at = DateTime.add(DateTime.utc_now(), expires_in, :second)
    jti_oidc = claims["jti"]

    with {:ok, access_token, jti} <-
           JWT.generate_access_token(
             to_string(workload_identity.id),
             "workload_identity",
             [scope],
             expires_in: expires_in
           ) do
      attrs = %{
        jti: jti,
        access_token: access_token,
        scopes: [scope],
        granted_scopes: [scope],
        expires_at: expires_at,
        grant_type: "workload_identity",
        grant_reference: jti_oidc,
        workload_identity_id: workload_identity.id,
        oidc_claims: provider.claims_snapshot(claims)
      }

      Repo.transaction(fn ->
        with :ok <- lock_still_matching(workload_identity, provider, claims),
             {:ok, token} <- Repo.insert(Token.build(attrs)) do
          token
        else
          {:error, reason} -> Repo.rollback(reason)
        end
      end)
      |> case do
        {:ok, token} ->
          {:ok, %{token | access_token: access_token}}

        {:error, %Ecto.Changeset{} = changeset} ->
          if unique_grant_reference_error?(changeset) do
            {:error, :token_replayed}
          else
            {:error, changeset}
          end

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  # A change locks the workload identity's row while it saves and revokes its
  # tokens. Matching the token's repository, workflow and environment again
  # under a shared lock means a token is either inserted before a change, which
  # then revokes it, or refused when the change stopped trusting its workflow.
  # The packages it covers are checked when the token is used.
  defp lock_still_matching(workload_identity, provider, claims) do
    current =
      Repo.one(
        from(wi in WorkloadIdentity, where: wi.id == ^workload_identity.id, lock: "FOR SHARE")
      )

    if current && provider.match?(current, claims),
      do: :ok,
      else: {:error, :no_matching_identity}
  end

  defp unique_grant_reference_error?(changeset) do
    Enum.any?(changeset.errors, fn
      {:grant_reference, {_msg, opts}} ->
        opts[:constraint_name] in [
          :oauth_tokens_workload_identity_grant_reference_index,
          "oauth_tokens_workload_identity_grant_reference_index"
        ]

      _ ->
        false
    end)
  end

  defp parse_id(id) when is_integer(id), do: {:ok, id}

  defp parse_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {int, ""} -> {:ok, int}
      _ -> :error
    end
  end

  defp parse_id(_), do: :error
end
