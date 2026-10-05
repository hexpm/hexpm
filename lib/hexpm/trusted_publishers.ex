defmodule Hexpm.TrustedPublishers do
  @moduledoc """
  Context for configuring trusted publishers and minting short-lived tokens.

  A package's publishers publish that package. An organization's publishers
  fetch from the organization's repository, and those with the `write` role
  also publish and create packages in it.
  """

  use Hexpm.Context

  alias Hexpm.OAuth.{JWT, Token}
  alias Hexpm.Repository.{Package, Repositories, Repository}
  alias Hexpm.TrustedPublishers.{OIDC, Provider, TrustedPublisher, VerifiedToken}

  @mint_expires_in 15 * 60

  def enabled? do
    features = Application.get_env(:hexpm, :features, [])
    Keyword.get(features, :trusted_publishers, false)
  end

  def audience, do: OIDC.audience()

  def list(%Package{} = package) do
    from(tp in TrustedPublisher, where: tp.package_id == ^package.id, order_by: [asc: tp.id])
    |> Repo.all()
  end

  def list(%Organization{} = organization) do
    from(tp in TrustedPublisher,
      where: tp.organization_id == ^organization.id,
      order_by: [asc: tp.id]
    )
    |> Repo.all()
  end

  @doc """
  Lists the organization's `write` publishers whose package list covers the
  package. A package in the public repository has none.
  """
  def list_covering(%Package{repository: %Repository{} = repository, name: name}) do
    repository
    |> organization_publishers_query(["write"], name)
    |> Repo.all()
  end

  def get(%Package{} = package, id) do
    case parse_id(id) do
      {:ok, id} -> Repo.get_by(TrustedPublisher, id: id, package_id: package.id)
      :error -> nil
    end
  end

  def get(%Organization{} = organization, id) do
    case parse_id(id) do
      {:ok, id} -> Repo.get_by(TrustedPublisher, id: id, organization_id: organization.id)
      :error -> nil
    end
  end

  def get(id) do
    case parse_id(id) do
      {:ok, id} -> Repo.get(TrustedPublisher, id)
      :error -> nil
    end
  end

  @doc """
  Adds a publisher to a package or to an organization.
  """
  def create(owner, params, opts)

  # The hexpm organization owns the public repository, which organization
  # publishers never cover.
  def create(%Organization{id: 1}, _params, _opts), do: {:error, :not_allowed}

  def create(owner, params, audit: audit_data) do
    provider_name = params["provider"] || params[:provider]

    with {:ok, provider} <- fetch_provider(provider_name) do
      params = normalize_create_params(params, provider)
      changeset = TrustedPublisher.changeset(%TrustedPublisher{}, params, owner)

      if changeset.valid? do
        resolve_attrs = %{
          repository: Ecto.Changeset.get_field(changeset, :repository),
          repository_owner: Ecto.Changeset.get_field(changeset, :repository_owner)
        }

        case provider.resolve_immutable_ids(resolve_attrs) do
          {:ok, immutable_ids} ->
            insert_publisher(owner, changeset, immutable_ids, audit_data)

          {:error, reason} ->
            {:error, reason}
        end
      else
        {:error, %{changeset | action: :insert}}
      end
    end
  end

  defp insert_publisher(owner, changeset, immutable_ids, audit_data) do
    changeset = TrustedPublisher.put_immutable_ids(changeset, immutable_ids)
    action = audit_action(owner, :add)

    multi =
      Multi.new()
      |> Multi.insert(:trusted_publisher, changeset)
      |> audit(audit_data, action, fn %{trusted_publisher: tp} -> preload_owner(tp) end)

    case Repo.transaction(multi) do
      {:ok, %{trusted_publisher: trusted_publisher}} ->
        trusted_publisher = preload_owner(trusted_publisher)
        notify(:added, trusted_publisher, audit_data)
        {:ok, trusted_publisher}

      {:error, _op, changeset, _} ->
        {:error, changeset}
    end
  end

  def delete(%TrustedPublisher{} = trusted_publisher, audit: audit_data) do
    trusted_publisher = preload_owner(trusted_publisher)
    action = audit_action(trusted_publisher.organization || trusted_publisher.package, :remove)

    multi =
      Multi.new()
      |> Multi.delete(:trusted_publisher, trusted_publisher)
      |> audit(audit_data, action, trusted_publisher)

    case Repo.transaction(multi) do
      {:ok, %{trusted_publisher: deleted}} ->
        notify(:removed, trusted_publisher, audit_data)
        {:ok, deleted}

      {:error, _op, changeset, _} ->
        {:error, changeset}
    end
  end

  defp audit_action(%Organization{}, :add), do: "organization.trusted_publisher.add"
  defp audit_action(%Organization{}, :remove), do: "organization.trusted_publisher.remove"
  defp audit_action(%Package{}, :add), do: "trusted_publisher.create"
  defp audit_action(%Package{}, :remove), do: "trusted_publisher.remove"

  defp preload_owner(%TrustedPublisher{} = trusted_publisher) do
    Repo.preload(trusted_publisher, [:organization, package: :repository])
  end

  # Not an optional email: a publisher grants publish rights to whoever can run
  # the workflow, so every owner, or every organization admin, hears about it.
  defp notify(event, %TrustedPublisher{organization: %Organization{} = organization} = tp, audit) do
    organization = %{
      organization
      | organization_users: Organizations.all_members(organization, user: :emails)
    }

    email =
      case event do
        :added -> Emails.organization_trusted_publisher_added(tp, organization, audit.user)
        :removed -> Emails.organization_trusted_publisher_removed(tp, organization, audit.user)
      end

    if email.to != [] do
      Mailer.deliver!(email)
    end
  end

  defp notify(event, %TrustedPublisher{package: package} = trusted_publisher, audit_data) do
    owners =
      package
      |> Owners.all(user: [:emails, organization: [organization_users: [user: :emails]]])
      |> Enum.map(& &1.user)

    if owners != [] do
      case event do
        :added -> Emails.trusted_publisher_added(trusted_publisher, owners, audit_data.user)
        :removed -> Emails.trusted_publisher_removed(trusted_publisher, owners, audit_data.user)
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
  (default `"hexpm"`), and the package's own publishers are tried before the
  organization's `write` publishers that cover the name. The package doesn't
  have to exist for an organization publisher, which can create it.

  Without `:package`, the token is scoped to the organization repository named
  by `:repository`, and any of the organization's publishers can match.
  """
  def mint(%VerifiedToken{provider: provider, claims: claims}, opts) do
    with :ok <- provider.validate_claims(claims),
         {:ok, repository} <- fetch_repository(opts),
         {:ok, trusted_publisher, scope} <- find_publisher(repository, provider, claims, opts),
         :ok <- check_billing(repository),
         {:ok, token} <- mint_token(trusted_publisher, scope, claims, provider) do
      :telemetry.execute([:hexpm, :trusted_publishers, :mint, :success], %{count: 1}, %{
        provider: provider.name(),
        package_id: trusted_publisher.package_id,
        organization_id: trusted_publisher.organization_id
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
    :telemetry.execute([:hexpm, :trusted_publishers, :mint, :failure], %{count: 1}, %{
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

  defp find_publisher(repository, provider, claims, opts) do
    case Keyword.fetch(opts, :package) do
      {:ok, package_name} -> find_package_publisher(repository, package_name, provider, claims)
      :error -> find_repository_publisher(repository, provider, claims)
    end
  end

  defp find_package_publisher(repository, package_name, provider, claims) do
    package = Packages.get(repository, package_name)

    package_publishers =
      if package do
        from(tp in TrustedPublisher,
          where: tp.package_id == ^package.id and tp.provider == ^provider.name(),
          order_by: [asc: tp.id]
        )
        |> Repo.all()
      else
        []
      end

    organization_publishers =
      repository
      |> organization_publishers_query(["write"], package_name)
      |> for_provider(provider)
      |> Repo.all()

    publishers = package_publishers ++ organization_publishers

    case Enum.find(publishers, &provider.match?(&1, claims)) do
      nil ->
        if is_nil(package) and publishers == [],
          do: {:error, :package_not_found},
          else: {:error, :no_matching_publisher}

      trusted_publisher ->
        {:ok, trusted_publisher, "package:#{repository.name}/#{package_name}"}
    end
  end

  defp find_repository_publisher(%Repository{id: 1}, _provider, _claims) do
    {:error, :no_matching_publisher}
  end

  defp find_repository_publisher(repository, provider, claims) do
    repository
    |> organization_publishers_query(TrustedPublisher.roles(), nil)
    |> for_provider(provider)
    |> Repo.all()
    |> Enum.find(&provider.match?(&1, claims))
    |> case do
      nil -> {:error, :no_matching_publisher}
      trusted_publisher -> {:ok, trusted_publisher, "repository:#{repository.name}"}
    end
  end

  defp organization_publishers_query(%Repository{id: 1}, _roles, _package_name) do
    from(tp in TrustedPublisher, where: false)
  end

  defp organization_publishers_query(%Repository{} = repository, roles, package_name) do
    query =
      from(tp in TrustedPublisher,
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

  defp mint_token(trusted_publisher, scope, claims, provider) do
    expires_in = @mint_expires_in
    expires_at = DateTime.add(DateTime.utc_now(), expires_in, :second)
    jti_oidc = claims["jti"]

    with {:ok, access_token, jti} <-
           JWT.generate_access_token(
             to_string(trusted_publisher.id),
             "trusted_publisher",
             [scope],
             expires_in: expires_in
           ) do
      attrs = %{
        jti: jti,
        access_token: access_token,
        scopes: [scope],
        granted_scopes: [scope],
        expires_at: expires_at,
        grant_type: "trusted_publisher",
        grant_reference: jti_oidc,
        trusted_publisher_id: trusted_publisher.id,
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
          :oauth_tokens_trusted_publisher_grant_reference_index,
          "oauth_tokens_trusted_publisher_grant_reference_index"
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
