defmodule Hexpm.TrustedPublishers do
  @moduledoc """
  Context for configuring trusted publishers and minting short-lived publish tokens.
  """

  use Hexpm.Context

  alias Hexpm.OAuth.{Clients, JWT, Token}
  alias Hexpm.Repository.Package
  alias Hexpm.TrustedPublishers.{OIDC, Provider, TrustedPublisher}

  @mint_expires_in 15 * 60
  @client_id_env_key :trusted_publisher_oauth_client_id

  def enabled? do
    features = Application.get_env(:hexpm, :features, [])
    Keyword.get(features, :trusted_publishers, false)
  end

  def audience, do: OIDC.audience()

  def client_id do
    Application.fetch_env!(:hexpm, @client_id_env_key)
  end

  def list(%Package{} = package) do
    from(tp in TrustedPublisher, where: tp.package_id == ^package.id, order_by: [asc: tp.id])
    |> Repo.all()
  end

  def get(%Package{} = package, id) do
    case parse_id(id) do
      {:ok, id} -> Repo.get_by(TrustedPublisher, id: id, package_id: package.id)
      :error -> nil
    end
  end

  def get(id) do
    case parse_id(id) do
      {:ok, id} -> Repo.get(TrustedPublisher, id)
      :error -> nil
    end
  end

  def create(%Package{} = package, params, audit: audit_data) do
    provider_name = params["provider"] || params[:provider]

    with {:ok, provider} <- fetch_provider(provider_name) do
      params = normalize_create_params(params, provider)
      changeset = TrustedPublisher.changeset(%TrustedPublisher{}, params, package)

      if changeset.valid? do
        resolve_attrs = %{repository: Ecto.Changeset.get_field(changeset, :repository)}

        case provider.resolve_immutable_ids(resolve_attrs) do
          {:ok, immutable_ids} ->
            insert_publisher(changeset, immutable_ids, audit_data)

          {:error, reason} ->
            {:error, reason}
        end
      else
        {:error, changeset}
      end
    end
  end

  defp insert_publisher(changeset, immutable_ids, audit_data) do
    changeset = TrustedPublisher.put_immutable_ids(changeset, immutable_ids)

    multi =
      Multi.new()
      |> Multi.insert(:trusted_publisher, changeset)
      |> audit(audit_data, "trusted_publisher.create", fn %{trusted_publisher: tp} ->
        Repo.preload(tp, package: :repository)
      end)

    case Repo.transaction(multi) do
      {:ok, %{trusted_publisher: trusted_publisher}} ->
        {:ok, Repo.preload(trusted_publisher, package: :repository)}

      {:error, _op, changeset, _} ->
        {:error, changeset}
    end
  end

  def delete(%TrustedPublisher{} = trusted_publisher, audit: audit_data) do
    trusted_publisher = Repo.preload(trusted_publisher, package: :repository)

    multi =
      Multi.new()
      |> Multi.delete(:trusted_publisher, trusted_publisher)
      |> audit(audit_data, "trusted_publisher.remove", trusted_publisher)

    case Repo.transaction(multi) do
      {:ok, %{trusted_publisher: deleted}} -> {:ok, deleted}
      {:error, _op, changeset, _} -> {:error, changeset}
    end
  end

  @doc """
  Verifies an OIDC token and mints a short-lived package-scoped Hex access token.
  """
  def verify_and_mint(oidc_token, opts) when is_binary(oidc_token) do
    repository = Keyword.get(opts, :repository, "hexpm")
    package_name = Keyword.fetch!(opts, :package)
    audit_data = Keyword.get(opts, :audit)

    with :ok <- enabled_guard(),
         {:ok, peeked} <- OIDC.peek_claims(oidc_token),
         {:ok, issuer} <- fetch_issuer(peeked),
         {:ok, provider} <- fetch_provider_by_issuer(issuer),
         {:ok, claims} <- OIDC.verify(oidc_token, issuer),
         {:ok, package} <- fetch_package(repository, package_name),
         {:ok, trusted_publisher} <- find_matching_publisher(package, provider, claims),
         {:ok, token} <- mint_token(trusted_publisher, package, claims, audit_data, provider) do
      :telemetry.execute([:hexpm, :trusted_publishers, :mint, :success], %{count: 1}, %{
        provider: provider.name(),
        package_id: package.id
      })

      {:ok, token}
    else
      {:error, reason} = error ->
        emit_failure(reason)
        error
    end
  end

  def verify_and_mint(_, _), do: {:error, :invalid_token}

  defp enabled_guard do
    if enabled?(), do: :ok, else: {:error, :disabled}
  end

  defp fetch_issuer(%{"iss" => issuer}) when is_binary(issuer) and issuer != "" do
    {:ok, issuer}
  end

  defp fetch_issuer(_), do: {:error, :issuer_missing}

  defp emit_failure(%Ecto.Changeset{}), do: emit_failure(:changeset_error)

  defp emit_failure(reason) do
    :telemetry.execute([:hexpm, :trusted_publishers, :mint, :failure], %{count: 1}, %{
      reason: reason
    })
  end

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

  defp fetch_package(repository, package_name) do
    case Hexpm.Repository.Packages.get(repository, package_name) do
      nil -> {:error, :package_not_found}
      package -> {:ok, package}
    end
  end

  defp find_matching_publisher(%Package{} = package, provider, claims) do
    publishers =
      from(tp in TrustedPublisher,
        where: tp.package_id == ^package.id and tp.provider == ^provider.name()
      )
      |> Repo.all()

    case Enum.find(publishers, &provider.match?(&1, claims)) do
      nil -> {:error, :no_matching_publisher}
      trusted_publisher -> {:ok, Repo.preload(trusted_publisher, package: :repository)}
    end
  end

  defp mint_token(trusted_publisher, package, claims, audit_data, provider) do
    client_id = client_id()
    scope = package_scope(package)
    expires_in = @mint_expires_in
    expires_at = DateTime.add(DateTime.utc_now(), expires_in, :second)
    jti_oidc = claims["jti"]

    subject = "trusted_publisher:#{trusted_publisher.id}"

    with {:ok, client} <- fetch_client(client_id),
         {:ok, access_token, jti} <-
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
        client_id: client.client_id,
        trusted_publisher_id: trusted_publisher.id,
        oidc_claims: provider.claims_snapshot(claims)
      }

      multi =
        Multi.new()
        |> Multi.insert(:token, Token.build(attrs))
        |> maybe_audit_mint(audit_data, trusted_publisher, subject)

      case Repo.transaction(multi) do
        {:ok, %{token: token}} ->
          {:ok, %{token | access_token: access_token}}

        {:error, :token, changeset, _} ->
          if unique_grant_reference_error?(changeset) do
            {:error, :token_replayed}
          else
            {:error, changeset}
          end

        {:error, _op, reason, _} ->
          {:error, reason}
      end
    end
  end

  defp maybe_audit_mint(multi, nil, _trusted_publisher, _subject), do: multi

  defp maybe_audit_mint(multi, audit_data, trusted_publisher, subject) do
    audit(multi, audit_data, "trusted_publisher.mint", {trusted_publisher, subject})
  end

  defp fetch_client(client_id) do
    case Clients.get(client_id) do
      nil -> {:error, :oauth_client_missing}
      client -> {:ok, client}
    end
  end

  defp package_scope(%Package{repository: %{name: repo}, name: name}) do
    "package:#{repo}/#{name}"
  end

  defp unique_grant_reference_error?(changeset) do
    Enum.any?(changeset.errors, fn
      {:grant_reference, {_msg, opts}} ->
        opts[:constraint_name] in [
          :oauth_tokens_trusted_publisher_grant_reference_client_id_index,
          "oauth_tokens_trusted_publisher_grant_reference_client_id_index"
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
