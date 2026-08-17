defmodule Hexpm.TrustedPublishers.OIDCTest do
  use Hexpm.DataCase, async: false
  import Mox

  alias Hexpm.TrustedPublisherHelpers
  alias Hexpm.TrustedPublishers.OIDC

  @issuer "https://token.actions.githubusercontent.com"

  setup :verify_on_exit!

  setup do
    TrustedPublisherHelpers.stub_oidc_discovery()
    :ok
  end

  test "rejects alg none" do
    claims = TrustedPublisherHelpers.github_claims()
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
      Map.merge(TrustedPublisherHelpers.github_claims(), %{
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
      TrustedPublisherHelpers.sign_oidc_claims(
        Map.merge(TrustedPublisherHelpers.github_claims(), %{
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
      TrustedPublisherHelpers.sign_oidc_claims(
        Map.merge(TrustedPublisherHelpers.github_claims(), %{
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
      TrustedPublisherHelpers.sign_oidc_claims(
        Map.merge(TrustedPublisherHelpers.github_claims(), %{
          "iat" => now + 120,
          "nbf" => now - 30,
          "exp" => now + 600
        })
      )

    assert {:error, :issued_at_in_future} = OIDC.verify(token, @issuer)
  end

  test "rejects missing jti" do
    token =
      TrustedPublisherHelpers.sign_oidc_claims(
        Map.put(TrustedPublisherHelpers.github_claims(), "jti", "")
      )

    assert {:error, :jti_missing} = OIDC.verify(token, @issuer)
  end

  test "refetches the JWKS when the token is signed by a rotated key" do
    assert {:ok, _} =
             OIDC.verify(
               TrustedPublisherHelpers.sign_oidc_claims(TrustedPublisherHelpers.github_claims()),
               @issuer
             )

    rotated = TrustedPublisherHelpers.rsa_jwk(:rotated)

    TrustedPublisherHelpers.stub_oidc_discovery(
      keys: [{TrustedPublisherHelpers.rsa_jwk(), "test-kid"}, {rotated, "rotated-kid"}],
      clear_cache: false
    )

    :persistent_term.erase({OIDC, :jwks_refreshed_at, @issuer})

    token =
      TrustedPublisherHelpers.sign_oidc_claims(TrustedPublisherHelpers.github_claims(),
        jwk: rotated,
        kid: "rotated-kid"
      )

    assert {:ok, claims} = OIDC.verify(token, @issuer)
    assert claims["repository"] == "acme/widget"
  end

  test "keeps rejecting an unknown key while the refetch is on cooldown" do
    assert {:ok, _} =
             OIDC.verify(
               TrustedPublisherHelpers.sign_oidc_claims(TrustedPublisherHelpers.github_claims()),
               @issuer
             )

    token =
      TrustedPublisherHelpers.sign_oidc_claims(TrustedPublisherHelpers.github_claims(),
        jwk: TrustedPublisherHelpers.rsa_jwk(:rotated),
        kid: "rotated-kid"
      )

    assert {:error, :signature_invalid} = OIDC.verify(token, @issuer)
  end

  test "accepts aud as a list containing hexpm" do
    token =
      TrustedPublisherHelpers.sign_oidc_claims(
        Map.put(TrustedPublisherHelpers.github_claims(), "aud", ["hexpm", "other"])
      )

    assert {:ok, _} = OIDC.verify(token, @issuer)
  end
end
