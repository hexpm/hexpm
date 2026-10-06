defmodule Hexpm.WorkloadIdentities.OIDCTest do
  use Hexpm.DataCase, async: false
  import Mox

  alias Hexpm.WorkloadIdentityHelpers
  alias Hexpm.WorkloadIdentities.OIDC

  @issuer "https://token.actions.githubusercontent.com"

  setup :verify_on_exit!

  setup do
    WorkloadIdentityHelpers.stub_oidc_discovery()
    :ok
  end

  test "rejects alg none" do
    claims = WorkloadIdentityHelpers.github_claims()
    now = System.system_time(:second)

    claims =
      Map.merge(
        %{
          "iss" => @issuer,
          "aud" => "hexpm",
          "iat" => now,
          "nbf" => now - 30,
          "exp" => now + 600,
          "jti" => "none-jti"
        },
        claims
      )

    # JOSE may refuse to sign with alg none; build a compact JWT manually.
    header = Base.url_encode64(~s({"alg":"none","typ":"JWT"}), padding: false)
    payload = Base.url_encode64(JSON.encode!(claims), padding: false)
    token = header <> "." <> payload <> "."

    assert {:error, :algorithm_rejected} = OIDC.verify(token, @issuer)
  end

  test "rejects HS256" do
    claims =
      Map.merge(WorkloadIdentityHelpers.github_claims(), %{
        "iss" => @issuer,
        "aud" => "hexpm",
        "iat" => System.system_time(:second),
        "nbf" => System.system_time(:second) - 30,
        "exp" => System.system_time(:second) + 600,
        "jti" => "hs-jti"
      })

    jwk = JOSE.JWK.from_oct(:crypto.strong_rand_bytes(32))
    {_, signed} = JOSE.JWT.sign(jwk, %{"alg" => "HS256"}, claims)
    {_, token} = JOSE.JWS.compact(signed)

    assert {:error, :algorithm_rejected} = OIDC.verify(token, @issuer)
  end

  test "rejects expired tokens" do
    now = System.system_time(:second)

    token =
      WorkloadIdentityHelpers.sign_oidc_claims(
        Map.merge(WorkloadIdentityHelpers.github_claims(), %{
          "exp" => now - 120,
          "nbf" => now - 200,
          "iat" => now - 200
        })
      )

    assert {:error, :token_expired} = OIDC.verify(token, @issuer)
  end

  test "rejects not-yet-valid tokens" do
    now = System.system_time(:second)

    token =
      WorkloadIdentityHelpers.sign_oidc_claims(
        Map.merge(WorkloadIdentityHelpers.github_claims(), %{
          "nbf" => now + 120,
          "iat" => now,
          "exp" => now + 600
        })
      )

    assert {:error, :token_not_yet_valid} = OIDC.verify(token, @issuer)
  end

  test "rejects issued-at-in-future tokens" do
    now = System.system_time(:second)

    token =
      WorkloadIdentityHelpers.sign_oidc_claims(
        Map.merge(WorkloadIdentityHelpers.github_claims(), %{
          "iat" => now + 120,
          "nbf" => now - 30,
          "exp" => now + 600
        })
      )

    assert {:error, :issued_at_in_future} = OIDC.verify(token, @issuer)
  end

  test "rejects tokens valid for longer than a Hex token" do
    now = System.system_time(:second)

    token =
      WorkloadIdentityHelpers.sign_oidc_claims(
        Map.merge(WorkloadIdentityHelpers.github_claims(), %{"iat" => now, "exp" => now + 3600})
      )

    assert {:error, :lifetime_too_long} = OIDC.verify(token, @issuer)
  end

  test "rejects missing jti" do
    token =
      WorkloadIdentityHelpers.sign_oidc_claims(
        Map.put(WorkloadIdentityHelpers.github_claims(), "jti", "")
      )

    assert {:error, :jti_missing} = OIDC.verify(token, @issuer)
  end

  test "refetches the JWKS when the token is signed by a rotated key" do
    assert {:ok, _} =
             OIDC.verify(
               WorkloadIdentityHelpers.sign_oidc_claims(WorkloadIdentityHelpers.github_claims()),
               @issuer
             )

    rotated = WorkloadIdentityHelpers.rsa_jwk(:rotated)

    WorkloadIdentityHelpers.stub_oidc_discovery(
      keys: [{WorkloadIdentityHelpers.rsa_jwk(), "test-kid"}, {rotated, "rotated-kid"}],
      clear_cache: false
    )

    :ets.delete(OIDC, @issuer)

    token =
      WorkloadIdentityHelpers.sign_oidc_claims(WorkloadIdentityHelpers.github_claims(),
        jwk: rotated,
        kid: "rotated-kid"
      )

    assert {:ok, claims} = OIDC.verify(token, @issuer)
    assert claims["repository"] == "acme/widget"
  end

  test "keeps rejecting an unknown key while the refetch is on cooldown" do
    assert {:ok, _} =
             OIDC.verify(
               WorkloadIdentityHelpers.sign_oidc_claims(WorkloadIdentityHelpers.github_claims()),
               @issuer
             )

    token =
      WorkloadIdentityHelpers.sign_oidc_claims(WorkloadIdentityHelpers.github_claims(),
        jwk: WorkloadIdentityHelpers.rsa_jwk(:rotated),
        kid: "rotated-kid"
      )

    assert {:error, :signature_invalid} = OIDC.verify(token, @issuer)
  end

  test "renews the cache expiry when the refetched JWKS is unchanged" do
    verify = fn ->
      OIDC.verify(
        WorkloadIdentityHelpers.sign_oidc_claims(WorkloadIdentityHelpers.github_claims()),
        @issuer
      )
    end

    assert {:ok, _} = verify.()

    expire_cache()
    :ets.delete(OIDC, @issuer)

    assert {:ok, _} = verify.()

    refute_fetch()

    assert {:ok, _} = verify.()
  end

  test "doesn't fetch the keys again for a bad signature under a known key ID" do
    assert {:ok, _} = OIDC.verify(github_token(), @issuer)

    :ets.delete(OIDC, @issuer)
    refute_fetch()

    token = github_token(jwk: WorkloadIdentityHelpers.rsa_jwk(:rotated), kid: "test-kid")
    assert {:error, :signature_invalid} = OIDC.verify(token, @issuer)
  end

  test "fetches the keys at most once per interval, failed fetches included" do
    test_pid = self()

    stub(Hexpm.HTTP.Mock, :get, fn url, _headers, _opts ->
      send(test_pid, {:fetched, url})
      {:ok, 503, [], ""}
    end)

    assert {:error, :http_status} = OIDC.verify(github_token(), @issuer)
    assert_received {:fetched, _url}

    assert {:error, :jwks_unavailable} = OIDC.verify(github_token(), @issuer)
    refute_received {:fetched, _url}
  end

  test "keeps using expired keys while another request holds the refresh" do
    assert {:ok, _} = OIDC.verify(github_token(), @issuer)

    expire_cache()
    refute_fetch()

    assert {:ok, _} = OIDC.verify(github_token(), @issuer)
  end

  test "keeps using expired keys when fetching them fails" do
    assert {:ok, _} = OIDC.verify(github_token(), @issuer)

    expire_cache()
    :ets.delete(OIDC, @issuer)
    stub(Hexpm.HTTP.Mock, :get, fn _url, _headers, _opts -> {:ok, 503, [], ""} end)

    assert {:ok, _} = OIDC.verify(github_token(), @issuer)
  end

  test "accepts aud as a list containing hexpm" do
    token =
      WorkloadIdentityHelpers.sign_oidc_claims(
        Map.put(WorkloadIdentityHelpers.github_claims(), "aud", ["hexpm", "other"])
      )

    assert {:ok, _} = OIDC.verify(token, @issuer)
  end

  defp github_token(opts \\ []) do
    WorkloadIdentityHelpers.sign_oidc_claims(WorkloadIdentityHelpers.github_claims(), opts)
  end

  defp expire_cache do
    {:ok, jwks, kids, _expires_at} = :persistent_term.get({OIDC, :jwks, @issuer})
    expired = DateTime.add(DateTime.utc_now(), -1, :second)
    :persistent_term.put({OIDC, :jwks, @issuer}, {:ok, jwks, kids, expired})
  end

  defp refute_fetch do
    stub(Hexpm.HTTP.Mock, :get, fn url, _headers, _opts ->
      flunk("unexpected fetch of #{url}")
    end)
  end
end
