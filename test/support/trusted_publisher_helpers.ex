defmodule Hexpm.TrustedPublisherHelpers do
  @moduledoc false

  import Hexpm.Factory
  import Mox

  alias Hexpm.TrustedPublishers
  alias Hexpm.TrustedPublishers.OIDC

  @issuer "https://token.actions.githubusercontent.com"

  def ensure_oauth_client do
    client_id = TrustedPublishers.client_id()

    case Hexpm.Repo.get(Hexpm.OAuth.Client, client_id) do
      nil ->
        insert(:oauth_client,
          client_id: client_id,
          name: "Trusted Publisher",
          client_type: "public",
          allowed_grant_types: ["trusted_publisher"],
          allowed_scopes: ["package"],
          redirect_uris: []
        )

      client ->
        client
    end
  end

  def rsa_jwk(name \\ :default) do
    case :persistent_term.get({__MODULE__, :rsa_jwk, name}, :miss) do
      :miss ->
        jwk = JOSE.JWK.generate_key({:rsa, 2048})
        :persistent_term.put({__MODULE__, :rsa_jwk, name}, jwk)
        jwk

      jwk ->
        jwk
    end
  end

  def stub_oidc_discovery(opts \\ []) do
    keys = Keyword.get(opts, :keys, [{rsa_jwk(), "test-kid"}])
    jwks_document = %{"keys" => Enum.map(keys, &public_jwk_map/1)}

    discovery = %{
      "issuer" => @issuer,
      "jwks_uri" => @issuer <> "/.well-known/jwks"
    }

    stub(Hexpm.HTTP.Mock, :get, fn url, _headers, _opts ->
      cond do
        String.contains?(url, "/.well-known/openid-configuration") ->
          {:ok, 200, [{"content-type", "application/json"}, {"cache-control", "max-age=3600"}],
           JSON.encode!(discovery)}

        String.contains?(url, "/.well-known/jwks") ->
          {:ok, 200, [{"content-type", "application/json"}, {"cache-control", "max-age=3600"}],
           JSON.encode!(jwks_document)}

        true ->
          {:ok, 404, [], ""}
      end
    end)

    if Keyword.get(opts, :clear_cache, true), do: OIDC.clear_cache()

    :ok
  end

  defp public_jwk_map({jwk, kid}) do
    {_, public_map} = jwk |> JOSE.JWK.to_public() |> JOSE.JWK.to_map()
    Map.put(public_map, "kid", kid)
  end

  def sign_oidc_claims(claims, opts \\ []) do
    jwk = Keyword.get(opts, :jwk, rsa_jwk())
    kid = Keyword.get(opts, :kid, "test-kid")
    now = System.system_time(:second)

    claims =
      Map.merge(
        %{
          "iss" => @issuer,
          "sub" => "repo:acme/widget:ref:refs/heads/main",
          "aud" => OIDC.audience(),
          "iat" => now,
          "nbf" => now - 30,
          "exp" => now + 600,
          "jti" => "oidc-jti-#{System.unique_integer([:positive])}"
        },
        claims
      )

    {_, signed} = JOSE.JWT.sign(jwk, %{"alg" => "RS256", "kid" => kid}, claims)
    {_, compact} = JOSE.JWS.compact(signed)
    compact
  end

  def github_claims(opts \\ []) do
    owner = Keyword.get(opts, :repository_owner, "acme")
    repo = Keyword.get(opts, :repository, "#{owner}/widget")
    workflow = Keyword.get(opts, :workflow, "release.yml")
    owner_id = Keyword.get(opts, :repository_owner_id, "12345")
    repo_id = Keyword.get(opts, :repository_id, "67890")
    environment = Keyword.get(opts, :environment)

    workflow_ref = "#{repo}/.github/workflows/#{workflow}@refs/heads/main"

    claims = %{
      "repository" => repo,
      "repository_owner" => owner,
      "repository_owner_id" => owner_id,
      "repository_id" => repo_id,
      "workflow_ref" => workflow_ref,
      "job_workflow_ref" => workflow_ref
    }

    if environment do
      Map.put(claims, "environment", environment)
    else
      claims
    end
  end
end
