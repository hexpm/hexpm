defmodule Hexpm.Repository.StagedReleases do
  use Hexpm.Context

  alias Hexpm.FeatureFlags
  alias Hexpm.Permissions
  alias Hexpm.OAuth.Token
  alias Hexpm.Repository.{StagedRelease, StagedReleaseCleanupWorker, StagedReleasePublishWorker}
  alias Hexpm.WorkloadIdentities.{Provider, WorkloadIdentity}
  alias HexpmWeb.AuthHelpers

  @lifetime 7 * 24 * 60 * 60
  @publish_timeout 60_000

  def enabled?(target),
    do: not is_nil(target) && FeatureFlags.enabled?(:workload_identity, target)

  def required?(_repository, _package, nil), do: false

  def required?(repository, package, audit) do
    target = policy_target(repository, package, audit)

    automated?(audit) && policy_required?(repository, package, target)
  end

  def approval_required?(%Package{id: id}) do
    if FeatureFlags.available?(:workload_identity) do
      package =
        Repo.one!(
          from(p in Package,
            join: r in assoc(p, :repository),
            left_join: o in assoc(r, :organization),
            where: p.id == ^id,
            preload: [repository: {r, organization: o}]
          )
        )

      policy_required?(
        package.repository,
        package,
        policy_target(package.repository, package, nil)
      )
    else
      false
    end
  end

  def approval_required?(%Organization{id: id}) do
    if FeatureFlags.available?(:workload_identity) do
      organization = Repo.get!(Organization, id)

      (enabled?(organization) && organization.require_publish_approval) ||
        Enum.any?(approval_packages(id), fn package ->
          policy_required?(
            package.repository,
            package,
            policy_target(package.repository, package, nil)
          )
        end) ||
        (enabled?(organization) &&
           Repo.exists?(
             from(s in StagedRelease,
               left_join: p in Package,
               on: p.repository_id == s.repository_id and p.name == s.name,
               where: is_nil(p.id),
               where: s.organization_id == ^id and s.repository_id == 1,
               where: s.expires_at > ^DateTime.utc_now() or not is_nil(s.publication)
             )
           ))
    else
      false
    end
  end

  defp approval_packages(organization_id) do
    Repo.all(
      from(p in Package,
        join: r in assoc(p, :repository),
        left_join: po in assoc(p, :package_owners),
        left_join: u in assoc(po, :user),
        where: r.organization_id == ^organization_id or u.organization_id == ^organization_id,
        where: p.require_publish_approval,
        distinct: true,
        preload: [repository: :organization]
      )
    )
  end

  def protected_packages(%Organization{id: id}) do
    from(p in Package,
      join: r in assoc(p, :repository),
      left_join: po in assoc(p, :package_owners),
      left_join: u in assoc(po, :user),
      where: r.organization_id == ^id or u.organization_id == ^id,
      distinct: true,
      preload: [repository: :organization]
    )
    |> filter_protected_packages()
  end

  def protected_packages(%User{id: id}) do
    from(p in Package,
      join: r in assoc(p, :repository),
      left_join: po in assoc(p, :package_owners),
      left_join: u in assoc(po, :user),
      left_join: m in OrganizationUser,
      on:
        m.user_id == ^id and
          (m.organization_id == r.organization_id or m.organization_id == u.organization_id),
      where:
        po.user_id == ^id or (m.role in ["admin", "write"] and r.id != 1) or
          (m.role in ["admin", "write"] and m.organization_id == u.organization_id),
      distinct: true,
      preload: [repository: :organization]
    )
    |> filter_protected_packages()
  end

  defp filter_protected_packages(query) do
    if FeatureFlags.available?(:workload_identity) do
      query
      |> Repo.all()
      |> Enum.filter(&policy_required?(&1.repository, &1, policy_target(&1.repository, &1, nil)))
      |> Enum.sort_by(&{&1.repository.name, &1.name})
    else
      []
    end
  end

  defp policy_required?(repository, package, target) do
    enabled?(target) &&
      (package_approval?(package) ||
         (repository.id != 1 && repository.organization.require_publish_approval))
  end

  defp automated?(audit) do
    match?(%WorkloadIdentity{}, audit.user) || match?(%Key{}, audit.auth_credential) ||
      match?(
        %Token{grant_type: "client_credentials", organization_id: id} when not is_nil(id),
        audit.auth_credential
      )
  end

  defp package_approval?(nil), do: %Package{}.require_publish_approval
  defp package_approval?(%Package{require_publish_approval: required}), do: required

  defp policy_target(%{id: 1}, nil, audit) do
    case audit.auth_credential do
      %{organization_id: id} when not is_nil(id) -> Repo.get!(Organization, id)
      _ -> audit.user
    end
  end

  defp policy_target(%{id: 1}, package, _audit), do: package
  defp policy_target(repository, _package, _audit), do: repository.organization

  @doc false
  def check_direct_policy(repository, package, audit, approved_by) do
    organization =
      Repo.one!(
        from(o in Organization, where: o.id == ^repository.organization_id, lock: "FOR SHARE")
      )

    repository = %{repository | organization: organization}

    package =
      if package && automated?(audit),
        do: Repo.one!(from(p in Package, where: p.id == ^package.id, lock: "FOR NO KEY UPDATE")),
        else: package

    audit =
      case audit do
        %{user: %WorkloadIdentity{id: id}} ->
          identity =
            Repo.one(from(wi in WorkloadIdentity, where: wi.id == ^id, lock: "FOR SHARE"))

          %{audit | user: identity}

        _ ->
          audit
      end

    if is_nil(approved_by) &&
         (required?(repository, package, audit) ||
            (match?(%Token{grant_type: "workload_identity"}, audit.auth_credential) &&
               is_nil(audit.user))),
       do: {:error, :staging_required},
       else: {:ok, :direct}
  end

  def reverts_blocked?(repository, package, audit), do: required?(repository, package, audit)

  def check_revert(release) do
    pending? =
      Repo.exists?(
        from(s in StagedRelease,
          where:
            s.repository_id == ^release.package.repository_id and
              s.name == ^release.package.name and s.version == ^release.version and
              not is_nil(s.publication)
        )
      )

    if pending?, do: {:error, version_error("is being published")}, else: {:ok, :available}
  end

  # Every release publish takes this lock, including a publish that creates a
  # package. There may be no package row to lock until approval creates it.
  def lock_name(repository, name),
    do: Repo.advisory_xact_lock(:staged_publish, sub_key: name_lock_key(repository.id, name))

  defp name_lock_key(repository_id, name), do: :erlang.phash2({repository_id, name})

  def check_reservation(repository, meta, allowed_id) do
    lock_name(repository, meta["name"])

    query =
      from(s in StagedRelease,
        where:
          s.repository_id == ^repository.id and s.name == ^meta["name"] and
            s.version == ^meta["version"] and s.kind == "release"
      )

    staged = Repo.one(query)

    if is_nil(staged) || staged.id == allowed_id,
      do: {:ok, :available},
      else: {:error, version_error("is awaiting approval")}
  end

  def stage(repository, body, meta, inner, outer, opts) do
    store_artifact(body, fn storage_key ->
      Repo.transaction(fn ->
        lock_name(repository, meta["name"])
        lock_repository(repository)
        package = Packages.get(repository, meta["name"])

        credential =
          authorize_credential!(repository, package, credential_attrs(opts[:audit]), meta["name"])

        publisher = publisher(credential)

        case Releases.validate_staged(repository, package, publisher, meta, inner, outer, opts) do
          {:ok, _} -> :ok
          {:error, changeset} -> Repo.rollback(changeset)
        end

        previous = find(repository, meta["name"], meta["version"], "release")

        if previous && not same_credential?(previous, credential_attrs(opts[:audit])),
          do: Repo.rollback(:different_credential)

        attrs =
          Map.merge(credential_attrs(opts[:audit]), %{
            repository_id: repository.id,
            name: meta["name"],
            version: meta["version"],
            kind: "release",
            meta: metadata_snapshot(meta),
            replace: opts[:replace] || false,
            inner_checksum: inner,
            outer_checksum: outer,
            storage_key: storage_key,
            expires_at: release_expires_at(repository, package, meta["version"]),
            audit_data: audit_snapshot(opts[:audit])
          })

        # Documentation belongs to the tarball the approver reviewed. A new
        # tarball has to upload its own docs, even if the version is unchanged.
        attrs = Map.merge(attrs, %{docs_storage_key: nil, docs_checksum: nil})
        staged = save!(previous, attrs, repository)
        audit!(opts[:audit], "release.stage", staged)
        notify(staged, :staged)
        enqueue_cleanup(previous)
        staged
      end)
    end)
    |> stage_result()
  end

  def stage_docs(repository, name, version, body, audit) do
    store_artifact(body, fn storage_key ->
      Repo.transaction(fn ->
        lock_name(repository, name)
        lock_repository(repository)
        package = Packages.get(repository, name)
        attrs = credential_attrs(audit)
        authorize_credential!(repository, package, attrs, name)
        release_stage = find(repository, name, version, "release")
        previous = release_stage || find(repository, name, version, "docs")

        if previous && not same_credential?(previous, attrs),
          do: Repo.rollback(:different_credential)

        if is_nil(release_stage) && (is_nil(package) || is_nil(Releases.get(package, version))),
          do: Repo.rollback(:not_found)

        if previous && expired?(previous), do: Repo.rollback(:expired)

        attrs =
          if release_stage,
            do: %{},
            else:
              Map.merge(attrs, %{
                repository_id: repository.id,
                name: name,
                version: version,
                kind: "docs",
                expires_at: DateTime.add(DateTime.utc_now(), @lifetime),
                audit_data: audit_snapshot(audit)
              })

        attrs =
          Map.merge(attrs, %{
            docs_storage_key: storage_key,
            docs_checksum: Assets.file_checksum(body)
          })

        staged = save!(previous, attrs, repository)
        audit!(audit, "release.stage", staged)
        if is_nil(release_stage), do: notify(staged, :staged)

        if previous && previous.docs_storage_key,
          do: StagedReleaseCleanupWorker.enqueue([previous.docs_storage_key])

        staged
      end)
    end)
    |> stage_result()
  end

  def get(id) do
    with {id, ""} <- Integer.parse(to_string(id)),
         %StagedRelease{} = staged <- Repo.get(StagedRelease, id) do
      Repo.preload(staged, [:user, :organization, repository: :organization])
    else
      _ -> nil
    end
  end

  def staged_by?(staged, audit), do: same_credential?(staged, credential_attrs(audit))

  def find(repository, name, version, kind) do
    case Version.parse(to_string(version)) do
      {:ok, version} ->
        Repo.get_by(StagedRelease,
          repository_id: repository.id,
          name: name,
          version: version,
          kind: kind
        )

      :error ->
        nil
    end
  end

  def for_user(user, session_id) do
    organizations =
      Repo.all(
        from(m in OrganizationUser,
          where: m.user_id == ^user.id and m.role in ["write", "admin"],
          select: m.organization_id
        )
      )

    from(s in StagedRelease,
      join: r in assoc(s, :repository),
      left_join: p in Package,
      on: p.repository_id == s.repository_id and p.name == s.name,
      left_join: o in PackageOwner,
      on: o.package_id == p.id,
      left_join: owner in User,
      on: owner.id == o.user_id,
      where: not is_nil(s.publication) or s.expires_at > ^DateTime.utc_now(),
      where:
        (r.id != 1 and r.organization_id in ^organizations) or
          (is_nil(p.id) and r.id == 1 and
             (s.user_id == ^user.id or s.organization_id in ^organizations)) or
          (o.level in ^PackageOwner.level_or_higher("maintainer") and
             (o.user_id == ^user.id or owner.organization_id in ^organizations)),
      order_by: [desc: s.inserted_at],
      distinct: true
    )
    |> Repo.all()
    |> Repo.preload(repository: :organization)
    |> Enum.filter(&can_approve?(&1, user, session_id))
  end

  def can_approve?(staged, user, session_id \\ nil)
  def can_approve?(_staged, nil, _session_id), do: false

  def can_approve?(staged, %User{} = user, session_id) do
    user = Repo.preload(user, :emails)
    repository = staged.repository
    package = Packages.get(repository, staged.name)
    conn = authorization_conn(repository, package, nil, session_id)

    eligible_approver?(staged, package, user) &&
      new_package_access?(staged, package, user, session_id) &&
      AuthHelpers.package_owner(conn, user) == :ok &&
      AuthHelpers.organization_billing_active(conn, user) == :ok
  end

  def readable?(staged, audit, session_id \\ nil) do
    same_credential?(staged, credential_attrs(audit)) ||
      (match?(%User{}, audit.user) && can_approve?(staged, audit.user, session_id))
  end

  def expired?(staged),
    do:
      is_nil(staged.publication) && DateTime.compare(staged.expires_at, DateTime.utc_now()) != :gt

  def approve(id, user, checksum, opts) do
    directory = Hexpm.TmpDir.tmp_dir("staged-approval")

    try do
      result =
        Repo.transaction(fn -> approve_in_transaction(id, user, checksum, directory, opts) end,
          timeout: @publish_timeout
        )

      case result do
        {:ok, staged} -> complete_approval(staged.id)
        error -> error
      end
    after
      File.rm_rf!(directory)
    end
  end

  defp approve_in_transaction(id, user, checksum, directory, opts) do
    staged = lock_staged!(id)
    staged = lock_authorization(staged, user)

    if not can_approve?(staged, fresh_user(user), opts[:session_id]),
      do: Repo.rollback(:forbidden)

    if expired?(staged), do: Repo.rollback(:expired)
    if checksum != StagedRelease.checksum(staged), do: Repo.rollback(:changed)

    if staged.publication,
      do: staged,
      else: record_approval(staged, user, directory, opts)
  end

  defp record_approval(staged, user, directory, opts) do
    repository = staged.repository
    package = Packages.get(repository, staged.name)
    credential = authorize_credential!(repository, package, Map.from_struct(staged), staged.name)
    publisher = publisher(credential)
    _body = download!(staged.storage_key, staged.outer_checksum, directory, "release.tar")
    _docs = download!(staged.docs_storage_key, staged.docs_checksum, directory, "docs.tar.gz")
    audit = restore_audit(staged, credential)
    published = publish_approved(staged, package, publisher, audit, user)
    audit!(opts[:audit], "release.approve", staged)

    staged =
      Repo.update!(
        change(staged,
          publication: %{"release_id" => published.release.id, "approver_id" => user.id}
        )
      )

    StagedReleasePublishWorker.enqueue(staged.id)
    staged
  end

  defp publish_approved(%{kind: "release"} = staged, package, publisher, audit, user) do
    wi_context =
      if staged.workload_identity_id,
        do: %{
          workload_identity_id: staged.workload_identity_id,
          oidc_claims: claims_struct(staged.oidc_claims)
        }

    result =
      Releases.publish_transaction(
        staged.repository,
        package,
        publisher,
        staged.meta,
        staged.inner_checksum,
        staged.outer_checksum,
        audit: audit,
        replace: staged.replace,
        workload_identity: wi_context,
        staged_release_id: staged.id,
        approved_by_id: user.id
      )

    case result do
      {:ok, published} -> published
      {:error, _, reason, _} -> Repo.rollback(reason)
    end
  end

  defp publish_approved(staged, package, _publisher, _audit, _user) do
    release = package && Releases.get(package, staged.version)
    if is_nil(release), do: Repo.rollback(:not_found)
    %{package: package, release: release}
  end

  def complete_approval(id) do
    Hexpm.RepoBase.checkout(
      fn ->
        case get(id) do
          nil ->
            {:ok, :completed}

          staged ->
            lock = [sub_key: name_lock_key(staged.repository_id, staged.name)]
            Repo.advisory_lock(:staged_publish, lock)

            try do
              complete_approval_locked(id)
            after
              Repo.advisory_unlock(:staged_publish, lock)
            end
        end
      end,
      timeout: @publish_timeout
    )
  end

  defp complete_approval_locked(id) do
    case get(id) do
      nil ->
        {:ok, :completed}

      %{publication: nil} ->
        {:error, :not_approved}

      staged ->
        directory = Hexpm.TmpDir.tmp_dir("staged-publication")

        try do
          with {:ok, body} <-
                 download(staged.storage_key, staged.outer_checksum, directory, "release.tar"),
               {:ok, docs} <-
                 download(staged.docs_storage_key, staged.docs_checksum, directory, "docs.tar.gz") do
            release =
              Repo.get!(Release, staged.publication["release_id"])
              |> Repo.preload([:publisher, package: [repository: :organization]])

            published = %{
              release: release,
              approved_by: release,
              package: release.package,
              repository: release.package.repository
            }

            if docs do
              {:ok, _} =
                Releases.publish_docs(published.package, release, docs,
                  audit: publication_audit(staged),
                  approved_by_id: staged.publication["approver_id"]
                )
            end

            published =
              if staged.kind == "release" do
                {:ok, published} =
                  Releases.complete_publish({:ok, published}, release.publisher, body)

                published
              else
                published
              end

            {:ok, _} =
              Repo.transaction(fn ->
                Repo.delete!(staged)
                enqueue_cleanup(staged)
              end)

            {:ok, published}
          end
        after
          File.rm_rf!(directory)
        end
    end
  end

  defp publication_audit(staged) do
    actor =
      cond do
        staged.workload_identity_id -> Repo.get(WorkloadIdentity, staged.workload_identity_id)
        staged.organization_id -> Repo.get(Organization, staged.organization_id)
        staged.user_id -> Repo.get(User, staged.user_id)
        true -> nil
      end

    actor = actor || Repo.get(User, staged.publication["approver_id"])
    credential = if staged.key_id, do: Keys.get(staged.key_id)

    Map.merge(%{user: actor, auth_credential: credential}, %{
      user_agent: staged.audit_data["user_agent"],
      remote_ip: staged.audit_data["remote_ip"],
      request_id: staged.audit_data["request_id"]
    })
  end

  def reject(id, user, opts) do
    Repo.transaction(fn ->
      staged = lock_staged!(id)
      staged = lock_authorization(staged, user)

      if not can_approve?(staged, fresh_user(user), opts[:session_id]),
        do: Repo.rollback(:forbidden)

      if staged.publication, do: Repo.rollback(:publishing)
      audit!(opts[:audit], "release.reject", staged)
      Repo.delete!(staged)
      enqueue_cleanup(staged)
      staged
    end)
  end

  def expire do
    from(s in StagedRelease,
      where: is_nil(s.publication) and s.expires_at <= ^DateTime.utc_now(),
      select: s.id
    )
    |> Repo.all()
    |> Enum.each(fn id ->
      Repo.transaction(fn ->
        case get(id) do
          nil ->
            :ok

          staged ->
            lock_name(staged.repository, staged.name)

            case get(id) do
              nil ->
                :ok

              staged ->
                if expired?(staged) do
                  audit!(
                    %{user: nil, auth_credential: nil, user_agent: "Hexpm", remote_ip: nil},
                    "release.stage_expire",
                    staged
                  )

                  notify(staged, :expired)
                  Repo.delete!(staged)
                  enqueue_cleanup(staged)
                end
            end
        end
      end)
    end)

    :ok
  end

  def configure(%Package{} = package, user, enabled, opts) when is_boolean(enabled) do
    Repo.transaction(fn ->
      repository = Repo.get!(Repository, package.repository_id) |> Repo.preload(:organization)
      lock_repository(repository)

      package =
        Repo.one!(from(p in Package, where: p.id == ^package.id, lock: "FOR NO KEY UPDATE"))

      package = %{package | repository: repository}

      Repo.all(
        from(m in OrganizationUser,
          where: m.user_id == ^user.id and m.organization_id != ^repository.organization_id,
          lock: "FOR SHARE"
        )
      )

      user = Users.lock!(user)
      if not User.tfa_enabled?(user), do: Repo.rollback(:tfa_required)

      conn = authorization_conn(repository, package, nil, opts[:session_id])

      if not enabled?(package) ||
           AuthHelpers.package_owner(conn, user, owner_level: "full") != :ok,
         do: Repo.rollback(:forbidden)

      updated = Repo.update!(change(package, require_publish_approval: enabled))
      audit!(opts[:audit], "package.publish_approval.configure", updated)

      if package.require_publish_approval && not enabled do
        package_policy_recipients(package)
        |> Emails.publish_approval_disabled(package)
        |> enqueue_email("staged-publishing-policy")
      end

      updated
    end)
  end

  def configure(%Organization{} = organization, user, enabled, opts) when is_boolean(enabled) do
    Repo.transaction(fn ->
      organization =
        Repo.one!(
          from(o in Organization, where: o.id == ^organization.id, lock: "FOR NO KEY UPDATE")
        )

      user = Users.lock!(user)
      if not User.tfa_enabled?(user), do: Repo.rollback(:tfa_required)

      if Hexpm.Accounts.OrganizationAuth.check(organization, user, nil, opts[:session_id]) != :ok,
        do: Repo.rollback(:forbidden)

      if not enabled?(organization) || organization.id == 1 ||
           not Hexpm.Accounts.Organizations.access?(organization, user, "admin"),
         do: Repo.rollback(:forbidden)

      updated = Repo.update!(change(organization, require_publish_approval: enabled))
      audit!(opts[:audit], "organization.publish_approval.configure", updated)

      if organization.require_publish_approval && not enabled do
        Repo.all(
          from(m in OrganizationUser,
            join: u in assoc(m, :user),
            where: m.organization_id == ^organization.id and m.role == "admin",
            select: u
          )
        )
        |> Repo.preload(:emails)
        |> Emails.publish_approval_disabled(organization)
        |> enqueue_email("staged-publishing-policy")
      end

      updated
    end)
  end

  defp package_policy_recipients(package) do
    owners =
      Repo.all(
        from(o in PackageOwner,
          where: o.package_id == ^package.id and o.level == "full",
          select: o.user_id
        )
      )

    organizations =
      Repo.all(
        from(u in User,
          where: u.id in ^owners and not is_nil(u.organization_id),
          select: u.organization_id
        )
      )

    organizations =
      if package.repository_id == 1,
        do: organizations,
        else: [package.repository.organization_id | organizations]

    from(u in User,
      left_join: m in OrganizationUser,
      on: m.user_id == u.id,
      where: is_nil(u.organization_id),
      where: u.id in ^owners or (m.organization_id in ^organizations and m.role == "admin"),
      distinct: true
    )
    |> Repo.all()
    |> Repo.preload(:emails)
  end

  def delete_repository(repository) do
    Repo.all(from(s in StagedRelease, where: s.repository_id == ^repository.id))
    |> Enum.each(&enqueue_cleanup/1)

    Repo.delete_all(from(s in StagedRelease, where: s.repository_id == ^repository.id))
    :ok
  end

  defp lock_repository(repository) do
    Repo.one!(
      from(o in Organization, where: o.id == ^repository.organization_id, lock: "FOR SHARE")
    )
  end

  defp lock_staged!(id) do
    staged = get(id) || Repo.rollback(:not_found)
    lock_name(staged.repository, staged.name)
    get(id) || Repo.rollback(:not_found)
  end

  defp lock_authorization(staged, user) do
    organization =
      Repo.one(
        from(o in Organization,
          where: o.id == ^staged.repository.organization_id,
          lock: "FOR SHARE"
        )
      )

    if is_nil(organization), do: Repo.rollback(:forbidden)
    staged = %{staged | repository: %{staged.repository | organization: organization}}

    # Organization policy changes lock the organization before the user.
    # Package updates precede credential locks, as workload-identity edits do.
    package = Packages.get(staged.repository, staged.name)

    if package do
      Repo.one!(from(p in Package, where: p.id == ^package.id, lock: "FOR NO KEY UPDATE"))
      Repo.all(from(o in PackageOwner, where: o.package_id == ^package.id, lock: "FOR SHARE"))
    end

    Repo.all(
      from(m in OrganizationUser,
        where: m.user_id in ^Enum.reject([user.id, staged.user_id], &is_nil/1),
        where: m.organization_id != ^organization.id,
        lock: "FOR SHARE"
      )
    )

    Repo.one!(from(u in User, where: u.id == ^user.id, lock: "FOR SHARE"))
    staged
  end

  defp fresh_user(user), do: Repo.get!(User, user.id)

  defp authorize_credential!(repository, package, attrs, name) do
    credential = load_credential(attrs)
    actor = credential_actor(credential)
    conn = authorization_conn(repository, package, credential, nil)

    if is_nil(credential) || is_nil(actor) ||
         not credential_active?(credential, attrs, package) ||
         AuthHelpers.package_owner(conn, actor, package_name: name) != :ok ||
         AuthHelpers.organization_billing_active(conn, actor) != :ok,
       do: Repo.rollback(:credential_revoked)

    credential
  end

  defp load_credential(%{credential_type: "key", key_id: id}) when not is_nil(id) do
    Repo.one(from(k in Key, where: k.id == ^id, lock: "FOR SHARE"))
    |> Repo.preload([:user, organization: :user])
  end

  defp load_credential(%{credential_type: "workload_identity", workload_identity_id: id})
       when not is_nil(id),
       do: Repo.one(from(w in WorkloadIdentity, where: w.id == ^id, lock: "FOR SHARE"))

  defp load_credential(_), do: nil

  defp credential_active?(%Key{} = key, _attrs, package) do
    actor = credential_actor(key)

    not Key.revoked?(key) &&
      (not match?(%User{}, actor) ||
         (is_nil(actor.deactivated_at) &&
            User.verified_primary_email?(Repo.preload(actor, :emails)))) &&
      (Permissions.verify_access?(key, "api", "write") ||
         Permissions.verify_access?(key, "publish", package))
  end

  defp credential_active?(%WorkloadIdentity{} = wi, attrs, _package) do
    provider = Provider.get(wi.provider)

    target =
      if wi.organization_id,
        do: Repo.get(Organization, wi.organization_id),
        else: Repo.get(Package, wi.package_id) |> Repo.preload(:repository)

    target && WorkloadIdentities.enabled?(target) && provider &&
      provider.match?(wi, attrs.oidc_claims)
  end

  defp credential_active?(_, _, _), do: false

  defp credential_actor(%Key{organization: %Organization{} = organization}), do: organization
  defp credential_actor(%Key{user: %User{} = user}), do: user
  defp credential_actor(%WorkloadIdentity{} = wi), do: wi
  defp credential_actor(_), do: nil
  defp publisher(%Key{organization: %Organization{user: user}}), do: user
  defp publisher(%Key{user: user}), do: user
  defp publisher(%WorkloadIdentity{}), do: nil

  defp authorization_conn(repository, package, credential, session_id) do
    %Plug.Conn{
      assigns: %{
        repository: repository,
        package: package,
        organization: repository.organization,
        auth_credential: credential,
        current_session: if(session_id, do: %{id: session_id})
      }
    }
  end

  defp credential_attrs(%{user: %WorkloadIdentity{} = wi, auth_credential: token}) do
    %{
      credential_type: "workload_identity",
      credential_name: "#{wi.provider} workload identity #{wi.id}",
      workload_identity_id: wi.id,
      key_id: nil,
      user_id: nil,
      organization_id: wi.organization_id,
      oidc_claims: snapshot(token.oidc_claims)
    }
  end

  defp credential_attrs(%{
         auth_credential: %Token{
           grant_type: "client_credentials",
           organization_id: organization_id,
           grant_reference: "key:" <> key_id
         }
       })
       when not is_nil(organization_id) do
    with {id, ""} <- Integer.parse(key_id),
         %Key{organization_id: ^organization_id} = key <- Keys.get(id) do
      credential_attrs(%{auth_credential: key})
    else
      _ -> %{}
    end
  end

  defp credential_attrs(%{auth_credential: %Key{} = key}) do
    %{
      credential_type: "key",
      credential_name: key.name,
      key_id: key.id,
      user_id: key.user_id,
      organization_id: key.organization_id,
      workload_identity_id: nil,
      oidc_claims: nil
    }
  end

  defp credential_attrs(_), do: %{}

  defp claims_struct(claims) do
    %Hexpm.WorkloadIdentities.ClaimsSnapshot{}
    |> Hexpm.WorkloadIdentities.ClaimsSnapshot.changeset(claims)
    |> apply_changes()
  end

  defp metadata_snapshot(value) when is_map(value),
    do: Map.new(value, fn {key, value} -> {key, metadata_snapshot(value)} end)

  defp metadata_snapshot(value) when is_list(value), do: Enum.map(value, &metadata_snapshot/1)

  defp metadata_snapshot(value) when is_tuple(value),
    do: value |> Tuple.to_list() |> metadata_snapshot()

  defp metadata_snapshot(value), do: value

  defp snapshot(%_{} = claims), do: claims |> Map.from_struct() |> Map.delete(:id) |> snapshot()

  defp snapshot(claims) when is_map(claims),
    do: Map.new(claims, fn {key, value} -> {to_string(key), value} end)

  # A replacement can only be approved while the public release is editable.
  defp release_expires_at(repository, package, version) do
    release = package && Releases.get(%{package | repository: repository}, version)

    lifetime =
      case release && Release.editable_until(release) do
        nil -> @lifetime
        until -> min(@lifetime, NaiveDateTime.diff(until, NaiveDateTime.utc_now()))
      end

    DateTime.add(DateTime.utc_now(), lifetime)
  end

  defp same_credential?(%{credential_type: "key", key_id: id}, %{key_id: id}) when not is_nil(id),
    do: true

  defp same_credential?(%{credential_type: "workload_identity", workload_identity_id: id}, %{
         workload_identity_id: id
       })
       when not is_nil(id), do: true

  defp same_credential?(_, _), do: false

  defp audit_snapshot(audit), do: Map.take(audit, [:user_agent, :remote_ip, :request_id])

  defp restore_audit(staged, credential) do
    %{
      user: credential_actor(credential),
      auth_credential: if(match?(%Key{}, credential), do: credential),
      user_agent: staged.audit_data["user_agent"],
      remote_ip: staged.audit_data["remote_ip"],
      request_id: staged.audit_data["request_id"]
    }
  end

  defp save!(previous, attrs, repository) do
    if previous && previous.publication, do: Repo.rollback(:publishing)

    case Repo.insert_or_update(StagedRelease.changeset(previous || %StagedRelease{}, attrs)) do
      {:ok, staged} -> %{staged | repository: repository}
      {:error, error} -> Repo.rollback(error)
    end
  end

  defp audit!(audit, action, value), do: Repo.insert!(AuditLog.build(audit, action, value))

  defp store_artifact(path, fun) do
    key = "staged/" <> Base.encode16(:crypto.strong_rand_bytes(24), case: :lower)
    {:ok, _} = Hexpm.Store.put_file(:repo_bucket, key, path, cache_control: "private, no-store")

    try do
      case fun.(key) do
        {:ok, _} = result ->
          result

        error ->
          StagedReleaseCleanupWorker.enqueue([key])
          error
      end
    rescue
      exception ->
        StagedReleaseCleanupWorker.enqueue([key])
        reraise exception, __STACKTRACE__
    end
  end

  defp download!(key, checksum, directory, filename) do
    case download(key, checksum, directory, filename) do
      {:ok, path} -> path
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp download(nil, _checksum, _directory, _filename), do: {:ok, nil}

  defp download(key, checksum, directory, filename) do
    path = Path.join(directory, filename)

    case Hexpm.Store.get_to_file(:repo_bucket, key, path) do
      result when result == :ok or elem(result, 0) == :ok ->
        if Assets.file_checksum(path) == checksum, do: {:ok, path}, else: {:error, :changed}

      _ ->
        {:error, :artifact_missing}
    end
  end

  defp enqueue_cleanup(nil), do: :ok

  defp enqueue_cleanup(staged),
    do:
      StagedReleaseCleanupWorker.enqueue(
        Enum.reject([staged.storage_key, staged.docs_storage_key], &is_nil/1)
      )

  defp notify(staged, event) do
    package = Packages.get(staged.repository, staged.name)
    {direct, organizations} = approver_ids(staged, package)

    approvers =
      from(u in User,
        left_join: m in OrganizationUser,
        on: m.user_id == u.id,
        where:
          is_nil(u.deactivated_at) and
            (u.id in ^direct or
               (m.organization_id in ^organizations and m.role in ["admin", "write"])),
        distinct: true
      )
      |> Repo.all()
      |> Repo.preload(:emails)
      |> Enum.filter(&eligible_approver?(staged, package, &1))

    if approvers != [],
      do: approvers |> Emails.staged_release(staged, event) |> enqueue_email("staged-release")
  end

  defp eligible_approver?(staged, package, user) do
    User.tfa_enabled?(user) && is_nil(user.deactivated_at) && User.verified_primary_email?(user) &&
      if is_nil(package) and staged.repository_id == 1,
        do: new_public_package_approver?(staged, user),
        else: AuthHelpers.package_owner(staged.repository, package, user, []) == :ok
  end

  defp new_public_package_approver?(%{organization_id: nil, user_id: id}, user),
    do: id == user.id

  defp new_public_package_approver?(staged, user),
    do:
      Hexpm.Accounts.Organizations.access?(
        Repo.get!(Organization, staged.organization_id),
        user,
        "write"
      )

  defp new_package_access?(%{repository_id: 1, organization_id: id}, nil, user, session_id)
       when not is_nil(id),
       do:
         Hexpm.Accounts.OrganizationAuth.check(Repo.get!(Organization, id), user, nil, session_id) ==
           :ok

  defp new_package_access?(_staged, _package, _user, _session_id), do: true

  defp approver_ids(%{repository_id: id, repository: repository}, nil) when id != 1,
    do: {[], [repository.organization_id]}

  defp approver_ids(staged, nil),
    do:
      {Enum.reject([staged.user_id], &is_nil/1), Enum.reject([staged.organization_id], &is_nil/1)}

  defp approver_ids(staged, package) do
    owners =
      Repo.all(
        from(o in PackageOwner,
          join: u in assoc(o, :user),
          where:
            o.package_id == ^package.id and o.level in ^PackageOwner.level_or_higher("maintainer"),
          select: {u.id, u.organization_id}
        )
      )

    organizations = Enum.reject(Enum.map(owners, &elem(&1, 1)), &is_nil/1)

    organizations =
      if staged.repository_id == 1,
        do: organizations,
        else: [staged.repository.organization_id | organizations]

    {Enum.map(owners, &elem(&1, 0)), organizations}
  end

  defp enqueue_email(email, category), do: Hexpm.Emails.Outbox.enqueue!(email, category: category)

  defp stage_result({:ok, staged}), do: {:ok, %{action: :staged, staged_release: staged}}
  defp stage_result({:error, error}), do: {:error, error}

  defp version_error(message), do: add_error(change(%Release{}), :version, message)
end
