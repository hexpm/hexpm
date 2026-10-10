defmodule Hexpm.WorkloadIdentities do
  @moduledoc """
  Context for configuring workload identities and minting short-lived tokens.

  A package's workload identities publish that package. An organization's workload identities
  fetch from the organization's repository, and those with the `write` role
  also publish and create packages in it.
  """

  use Hexpm.Context

  alias Hexpm.OAuth.{JWT, Token}
  alias Hexpm.Repository.{Package, Repositories, Repository}
  alias Hexpm.WorkloadIdentities.{OIDC, Provider, WorkloadIdentity, VerifiedToken}

  @mint_expires_in 15 * 60

  def enabled? do
    features = Application.get_env(:hexpm, :features, [])
    Keyword.get(features, :workload_identity, false)
  end

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
  Lists the organization's `write` workload identities whose package list covers the
  package. A package in the public repository has none.
  """
  def list_covering(%Package{repository: %Repository{} = repository, name: name}) do
    repository
    |> organization_identities_query(["write"], name)
    |> Repo.all()
  end

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
  for the owner and repository IDs, and refuses the add when it returns
  `{:error, reason}`.
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
    before_lookup = Keyword.get(opts, :before_lookup, fn -> :ok end)
    provider_name = params["provider"] || params[:provider]

    with {:ok, provider} <- fetch_provider(provider_name) do
      params = normalize_create_params(params, provider)
      changeset = WorkloadIdentity.changeset(%WorkloadIdentity{}, params, owner)

      if changeset.valid? do
        resolve_attrs = %{
          repository: Ecto.Changeset.get_field(changeset, :repository),
          repository_owner: Ecto.Changeset.get_field(changeset, :repository_owner)
        }

        with :ok <- before_lookup.(),
             {:ok, immutable_ids} <- provider.resolve_immutable_ids(resolve_attrs) do
          insert_identity(owner, changeset, immutable_ids, audit_data)
        end
      else
        {:error, %{changeset | action: :insert}}
      end
    end
  end

  defp insert_identity(owner, changeset, immutable_ids, audit_data) do
    changeset = WorkloadIdentity.put_immutable_ids(changeset, immutable_ids)
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

  def delete(%WorkloadIdentity{} = workload_identity, audit: audit_data) do
    workload_identity = preload_owner(workload_identity)
    action = audit_action(workload_identity.organization || workload_identity.package, :remove)

    multi =
      Multi.new()
      |> Multi.update_all(:tokens, revoke_tokens_query([workload_identity.id]), [])
      |> Multi.delete(:workload_identity, workload_identity)
      |> audit(audit_data, action, workload_identity)

    case Repo.transaction(multi) do
      {:ok, %{workload_identity: deleted}} ->
        notify(:removed, workload_identity, audit_data)
        {:ok, deleted}

      {:error, _op, changeset, _} ->
        {:error, changeset}
    end
  end

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
  defp audit_action(%Organization{}, :remove), do: "organization.workload_identity.remove"
  defp audit_action(%Package{}, :add), do: "workload_identity.create"
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
  workload identities, and a package in an organization's repository matches the
  organization's `write` workload identities that cover the name. The package doesn't
  have to exist for an organization workload identity, which can create it.

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
    if enabled?(), do: :ok, else: {:error, :disabled}
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

  defp normalize_create_params(params, provider) do
    params
    |> Map.new(fn {k, v} -> {to_string(k), v} end)
    |> Map.put("provider", provider.name())
    |> stringify_repository_id()
  end

  defp stringify_repository_id(%{"repository_id" => repository_id} = params)
       when is_integer(repository_id) do
    Map.put(params, "repository_id", Integer.to_string(repository_id))
  end

  defp stringify_repository_id(params), do: params

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

    with :ok <- check_package_name(package, package_name) do
      workload_identities =
        repository
        |> package_identities_query(package, package_name)
        |> for_provider(provider)
        |> Repo.all()

      case Enum.find(workload_identities, &provider.match?(&1, claims)) do
        nil ->
          if is_nil(package) and workload_identities == [],
            do: {:error, :package_not_found},
            else: {:error, :no_matching_identity}

        workload_identity ->
          {:ok, workload_identity, "package:#{repository.name}/#{package_name}"}
      end
    end
  end

  # Some existing packages predate the current name rules, so only a name that
  # no package has yet must be one a package can be created with.
  defp check_package_name(%Package{}, _package_name), do: :ok

  defp check_package_name(nil, package_name) do
    if WorkloadIdentity.valid_package_name?(package_name),
      do: :ok,
      else: {:error, :invalid_package_name}
  end

  defp package_identities_query(%Repository{id: 1}, nil = _package, _package_name) do
    from(tp in WorkloadIdentity, where: false)
  end

  defp package_identities_query(%Repository{id: 1}, %Package{} = package, _package_name) do
    from(tp in WorkloadIdentity, where: tp.package_id == ^package.id, order_by: [asc: tp.id])
  end

  defp package_identities_query(%Repository{} = repository, _package, package_name) do
    organization_identities_query(repository, ["write"], package_name)
  end

  defp find_repository_identity(%Repository{id: 1}, _provider, _claims) do
    {:error, :no_matching_identity}
  end

  defp find_repository_identity(repository, provider, claims) do
    repository
    |> organization_identities_query(WorkloadIdentity.roles(), nil)
    |> for_provider(provider)
    |> Repo.all()
    |> Enum.find(&provider.match?(&1, claims))
    |> case do
      nil -> {:error, :no_matching_identity}
      workload_identity -> {:ok, workload_identity, "repository:#{repository.name}"}
    end
  end

  defp organization_identities_query(%Repository{id: 1}, _roles, _package_name) do
    from(tp in WorkloadIdentity, where: false)
  end

  defp organization_identities_query(%Repository{} = repository, roles, package_name) do
    query =
      from(tp in WorkloadIdentity,
        where: tp.organization_id == ^repository.organization_id and tp.role in ^roles,
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

      case Repo.insert(Token.build(attrs)) do
        {:ok, token} ->
          {:ok, %{token | access_token: access_token}}

        {:error, changeset} ->
          if unique_grant_reference_error?(changeset) do
            {:error, :token_replayed}
          else
            {:error, changeset}
          end
      end
    end
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
