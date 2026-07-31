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

  def rsa_jwk do
    case :persistent_term.get({__MODULE__, :rsa_jwk}, :miss) do
      :miss ->
        jwk = JOSE.JWK.generate_key({:rsa, 2048})
        :persistent_term.put({__MODULE__, :rsa_jwk}, jwk)
        jwk

      jwk ->
        jwk
    end
  end

  def stub_oidc_discovery do
    public_jwk = JOSE.JWK.to_public(rsa_jwk())
    {_, public_map} = JOSE.JWK.to_map(public_jwk)
    jwks_document = %{"keys" => [Map.put(public_map, "kid", "test-kid")]}

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

    OIDC.clear_cache()
    :ok
  end

  def sign_oidc_claims(claims) do
    now = System.system_time(:second)

    claims =
      Map.merge(
        %{
          "iss" => @issuer,
          "aud" => OIDC.audience(),
          "iat" => now,
          "nbf" => now - 30,
          "exp" => now + 600,
          "jti" => "oidc-jti-#{System.unique_integer([:positive])}"
        },
        claims
      )

    {_, signed} = JOSE.JWT.sign(rsa_jwk(), %{"alg" => "RS256", "kid" => "test-kid"}, claims)
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
