defmodule Hexpm.Accounts.SSO.OIDC.OidccTest do
  use ExUnit.Case

  import Mox

  alias Hexpm.Accounts.SSO.{Connection, Error, SafeURL, Transaction}
  alias Hexpm.Accounts.SSO.OIDC.Oidcc

  defmodule SlowResolver do
    def getaddrs(_host, _family) do
      Process.sleep(100)
      {:ok, [{1, 1, 1, 1}]}
    end
  end

  defmodule EmptyResolver do
    def getaddrs(_host, _family), do: {:ok, []}
  end

  defmodule MixedResolver do
    def getaddrs(_host, :inet), do: {:ok, [{1, 1, 1, 1}]}
    def getaddrs(_host, :inet6), do: {:ok, [{0, 0, 0, 0, 0, 0, 0, 1}]}
  end

  @issuer "https://1.1.1.1/oauth2/default"
  @authorization_endpoint "https://1.1.1.1/oauth2/v1/authorize"
  @token_endpoint "https://1.1.1.1/oauth2/v1/token"
  @jwks_uri "https://1.1.1.1/oauth2/v1/keys"

  setup :verify_on_exit!

  setup do
    key = JOSE.JWK.generate_key({:rsa, 1_024})
    {_, public_key} = key |> JOSE.JWK.to_public_map()
    public_key = Map.put(public_key, "kid", "key-1")

    discovery_document = discovery_document()
    jwks_document = %{"keys" => [public_key]}

    connection = %Connection{
      issuer: @issuer,
      client_id: "client-id",
      client_secret: "client-secret",
      discovery_document: discovery_document,
      jwks_document: jwks_document
    }

    transaction = %Transaction{
      raw_state: "state",
      nonce: "nonce",
      code_verifier: String.duplicate("v", 43),
      redirect_uri: "https://hex.pm/sso/callback",
      inserted_at: DateTime.utc_now()
    }

    %{
      connection: connection,
      discovery_document: discovery_document,
      jwks_document: jwks_document,
      key: key,
      transaction: transaction
    }
  end

  test "discovers a standards-compliant provider without provider domain checks", context do
    expect_json_get(
      @issuer <> "/.well-known/openid-configuration",
      context.discovery_document,
      "max-age=600"
    )

    expect_json_get(@jwks_uri, context.jwks_document, "max-age=300")

    assert {:ok, metadata} = Oidcc.discover(@issuer)
    assert metadata.discovery_document == context.discovery_document
    assert metadata.jwks_document == context.jwks_document

    assert DateTime.compare(
             metadata.metadata_expires_at,
             DateTime.add(DateTime.utc_now(), 310, :second)
           ) == :lt
  end

  test "rejects discovery when the returned issuer is not exact", context do
    document = Map.put(context.discovery_document, "issuer", @issuer <> "/")

    expect_json_get(@issuer <> "/.well-known/openid-configuration", document)

    assert {:error, %Error{stage: :discovery, code: :issuer_mismatch}} =
             Oidcc.discover(@issuer)
  end

  test "rejects nonconforming issuer components before discovery" do
    assert {:error, %Error{stage: :url_validation, code: :query_not_allowed}} =
             Oidcc.discover(@issuer <> "?tenant=other")

    assert {:error, %Error{stage: :url_validation, code: :fragment_not_allowed}} =
             Oidcc.discover(@issuer <> "#other")
  end

  test "rejects a nonconforming stored issuer before authorization or token exchange", context do
    connection = %{context.connection | issuer: @issuer <> "?tenant=other"}

    assert {:error, %Error{stage: :url_validation, code: :query_not_allowed}} =
             Oidcc.authorization_uri(
               connection,
               context.transaction,
               context.transaction.redirect_uri,
               connection.client_secret
             )

    assert {:error, %Error{stage: :url_validation, code: :query_not_allowed}} =
             Oidcc.exchange_code(
               connection,
               context.transaction,
               "authorization-code",
               context.transaction.redirect_uri,
               connection.client_secret
             )
  end

  test "honors provider no-cache metadata policy", context do
    expect_json_get(
      @issuer <> "/.well-known/openid-configuration",
      context.discovery_document,
      "no-cache"
    )

    expect_json_get(@jwks_uri, context.jwks_document, "no-store")

    assert {:ok, metadata} = Oidcc.discover(@issuer)
    assert DateTime.diff(metadata.metadata_expires_at, DateTime.utc_now(), :second) in -1..1
  end

  test "parses Cache-Control directive names case-insensitively", context do
    expect_json_get(
      @issuer <> "/.well-known/openid-configuration",
      context.discovery_document,
      "MAX-AGE=120"
    )

    expect_json_get(@jwks_uri, context.jwks_document, "Max-Age=60")

    assert {:ok, metadata} = Oidcc.discover(@issuer)
    assert DateTime.diff(metadata.metadata_expires_at, DateTime.utc_now(), :second) in 58..60
  end

  test "subtracts shared-cache Age from provider metadata freshness", context do
    expect(Hexpm.HTTP.Mock, :get, fn _url, _headers, _opts ->
      {:ok, 200,
       [
         {"content-type", "application/json"},
         {"cache-control", "max-age=86400"},
         {"age", "86399"}
       ], JSON.encode!(context.discovery_document)}
    end)

    expect(Hexpm.HTTP.Mock, :get, fn @jwks_uri, _headers, _opts ->
      {:ok, 200,
       [
         {"content-type", "application/json"},
         {"cache-control", "max-age=86400"},
         {"age", "86399"}
       ], JSON.encode!(context.jwks_document)}
    end)

    assert {:ok, metadata} = Oidcc.discover(@issuer)
    assert DateTime.diff(metadata.metadata_expires_at, DateTime.utc_now(), :second) in 0..1
  end

  test "accepts the standard JWKS JSON media type", context do
    expect_json_get(
      @issuer <> "/.well-known/openid-configuration",
      context.discovery_document
    )

    expect(Hexpm.HTTP.Mock, :get, fn @jwks_uri, _headers, _opts ->
      {:ok, 200, [{"content-type", "application/jwk-set+json"}],
       JSON.encode!(context.jwks_document)}
    end)

    assert {:ok, _metadata} = Oidcc.discover(@issuer)
  end

  test "does not follow a discovery redirect" do
    expect(Hexpm.HTTP.Mock, :get, fn _url, _headers, _opts ->
      {:ok, 302, [{"location", "https://example.com/metadata"}], ""}
    end)

    assert {:error, %Error{stage: :discovery, code: :http_status}} =
             Oidcc.discover(@issuer)
  end

  test "rejects a discovery document that is not JSON" do
    expect(Hexpm.HTTP.Mock, :get, fn _url, _headers, _opts ->
      {:ok, 200, [{"content-type", "application/json"}], "{\"issuer\": "}
    end)

    assert {:error, %Error{stage: :discovery, code: :invalid_json}} = Oidcc.discover(@issuer)
  end

  test "rejects a discovery document served as another media type" do
    expect(Hexpm.HTTP.Mock, :get, fn _url, _headers, _opts ->
      {:ok, 200, [{"content-type", "text/html"}], "<html></html>"}
    end)

    assert {:error, %Error{stage: :discovery, code: :invalid_content_type}} =
             Oidcc.discover(@issuer)
  end

  test "rejects a provider that publishes no signing keys", context do
    expect_json_get(
      @issuer <> "/.well-known/openid-configuration",
      context.discovery_document
    )

    expect_json_get(@jwks_uri, %{"keys" => []})

    assert {:error, %Error{stage: :jwks, code: :invalid_document}} = Oidcc.discover(@issuer)
  end

  test "reports an oversized JWKS separately from a transport failure", context do
    expect_json_get(
      @issuer <> "/.well-known/openid-configuration",
      context.discovery_document
    )

    expect(Hexpm.HTTP.Mock, :get, fn @jwks_uri, _headers, _opts ->
      {:error, :response_too_large}
    end)

    assert {:error, %Error{stage: :jwks, code: :response_too_large}} = Oidcc.discover(@issuer)
  end

  test "rejects private-network issuer URLs before making a request" do
    assert {:error, %Error{stage: :url_validation, code: :private_address_not_allowed}} =
             SafeURL.validate("https://127.0.0.1/oauth2/default")

    assert {:error, %Error{stage: :url_validation, code: :private_address_not_allowed}} =
             SafeURL.validate("https://[::1]/oauth2/default")

    assert {:error, %Error{stage: :url_validation, code: :private_address_not_allowed}} =
             SafeURL.validate("https://[::7f00:1]/oauth2/default")

    assert {:error, %Error{stage: :url_validation, code: :private_address_not_allowed}} =
             SafeURL.validate("https://198.51.100.1/oauth2/default")
  end

  test "rejects special-use IPv6 issuer URLs before making a request" do
    addresses = [
      "1fff:ffff:ffff:ffff:ffff:ffff:ffff:ffff",
      "2001::",
      "2001:1ff:ffff:ffff:ffff:ffff:ffff:ffff",
      "2001:db8::",
      "2001:db8:ffff:ffff:ffff:ffff:ffff:ffff",
      "2002::",
      "2002:ffff:ffff:ffff:ffff:ffff:ffff:ffff",
      "3ffe::",
      "3ffe:ffff:ffff:ffff:ffff:ffff:ffff:ffff",
      "3fff::",
      "3fff:fff:ffff:ffff:ffff:ffff:ffff:ffff",
      "4000::",
      "::ffff:127.0.0.1",
      "::8.8.8.8"
    ]

    for address <- addresses do
      assert {:error, %Error{stage: :url_validation, code: :private_address_not_allowed}} =
               SafeURL.validate("https://[#{address}]/oauth2/default")
    end
  end

  test "accepts ordinary global-unicast IPv6 issuer URLs" do
    addresses = [
      "2001:200::",
      "2001:db7:ffff:ffff:ffff:ffff:ffff:ffff",
      "2001:db9::",
      "2003::",
      "2606:4700:4700::1111",
      "3fff:1000::",
      "::ffff:8.8.8.8"
    ]

    for address <- addresses do
      assert {:ok, %URI{host: ^address}} =
               SafeURL.validate("https://[#{address}]/oauth2/default")
    end
  end

  test "makes no request at all for a hostname that resolves to nothing" do
    original_resolver = Application.get_env(:hexpm, :sso_dns_resolver)
    Application.put_env(:hexpm, :sso_dns_resolver, EmptyResolver)

    on_exit(fn -> restore_env(:sso_dns_resolver, original_resolver) end)

    # No Hexpm.HTTP.Mock expectation: with no address there is nothing to pin
    # to, and an unpinned request would resolve the hostname again at connect
    # time, which is the rebinding this guard exists to stop. verify_on_exit!
    # fails the test if a request is made anyway.
    assert {:error, %Error{stage: :url_validation, code: :dns_resolution_failed}} =
             Oidcc.discover("https://nowhere.example/oauth2/default")
  end

  test "rejects a hostname when any resolved address is not public" do
    original_resolver = Application.get_env(:hexpm, :sso_dns_resolver)
    Application.put_env(:hexpm, :sso_dns_resolver, MixedResolver)

    on_exit(fn ->
      restore_env(:sso_dns_resolver, original_resolver)
    end)

    assert {:error, %Error{stage: :url_validation, code: :private_address_not_allowed}} =
             SafeURL.validate("https://mixed.example/oauth2/default")
  end

  test "ignores optional PAR metadata instead of making an uncontrolled server request",
       context do
    document =
      Map.put(
        context.discovery_document,
        "pushed_authorization_request_endpoint",
        "https://127.0.0.1/private-par"
      )

    expect_json_get(@issuer <> "/.well-known/openid-configuration", document)
    expect_json_get(@jwks_uri, context.jwks_document)
    assert {:ok, metadata} = Oidcc.discover(@issuer)

    connection = %{context.connection | discovery_document: metadata.discovery_document}

    assert {:ok, authorization_uri} =
             Oidcc.authorization_uri(
               connection,
               context.transaction,
               context.transaction.redirect_uri,
               connection.client_secret
             )

    assert URI.parse(authorization_uri).host == "1.1.1.1"
    assert URI.parse(authorization_uri).path == "/oauth2/v1/authorize"
  end

  test "rejects providers that require pushed authorization requests", context do
    document =
      context.discovery_document
      |> Map.put("require_pushed_authorization_requests", true)
      |> Map.put("pushed_authorization_request_endpoint", "https://1.1.1.1/par")

    expect_json_get(@issuer <> "/.well-known/openid-configuration", document)

    assert {:error, %Error{stage: :discovery, code: :pushed_authorization_requests_unsupported}} =
             Oidcc.discover(@issuer)
  end

  test "ignores optional signed request-object metadata", context do
    document =
      context.discovery_document
      |> Map.put("request_parameter_supported", true)
      |> Map.put("request_object_signing_alg_values_supported", ["HS256"])

    connection = %{context.connection | discovery_document: document}

    assert {:ok, authorization_uri} =
             Oidcc.authorization_uri(
               connection,
               context.transaction,
               context.transaction.redirect_uri,
               connection.client_secret
             )

    refute Map.has_key?(URI.decode_query(URI.parse(authorization_uri).query), "request")
  end

  test "rejects providers that require signed request objects", context do
    document =
      context.discovery_document
      |> Map.put("request_parameter_supported", true)
      |> Map.put("require_signed_request_object", true)
      |> Map.put("request_object_signing_alg_values_supported", ["HS256"])

    expect_json_get(@issuer <> "/.well-known/openid-configuration", document)

    assert {:error, %Error{stage: :discovery, code: :request_objects_unsupported}} =
             Oidcc.discover(@issuer)
  end

  test "accepts a provider that does not advertise code challenge methods", context do
    # Microsoft Entra omits code_challenge_methods_supported and accepts S256
    # anyway, so an absent list must not be read as a refusal.
    document = Map.delete(context.discovery_document, "code_challenge_methods_supported")

    expect_json_get(@issuer <> "/.well-known/openid-configuration", document)
    expect_json_get(@jwks_uri, context.jwks_document)

    assert {:ok, metadata} = Oidcc.discover(@issuer)
    assert metadata.discovery_document == document
  end

  test "still sends an S256 challenge to a provider that advertises nothing", context do
    document = Map.delete(context.discovery_document, "code_challenge_methods_supported")
    connection = %{context.connection | discovery_document: document}

    assert {:ok, authorization_uri} =
             Oidcc.authorization_uri(
               connection,
               context.transaction,
               context.transaction.redirect_uri,
               connection.client_secret
             )

    query = URI.decode_query(URI.parse(authorization_uri).query)
    assert query["code_challenge_method"] == "S256"
    assert is_binary(query["code_challenge"])
  end

  test "rejects a provider that advertises code challenge methods without S256", context do
    document = Map.put(context.discovery_document, "code_challenge_methods_supported", ["plain"])

    expect_json_get(@issuer <> "/.well-known/openid-configuration", document)

    assert {:error, %Error{stage: :discovery, code: :pkce_s256_unsupported}} =
             Oidcc.discover(@issuer)
  end

  test "bounds DNS resolution time" do
    original_resolver = Application.get_env(:hexpm, :sso_dns_resolver)
    original_timeout = Application.get_env(:hexpm, :sso_dns_timeout)
    Application.put_env(:hexpm, :sso_dns_resolver, SlowResolver)
    Application.put_env(:hexpm, :sso_dns_timeout, 10)

    on_exit(fn ->
      restore_env(:sso_dns_resolver, original_resolver)
      restore_env(:sso_dns_timeout, original_timeout)
    end)

    assert {:error, %Error{stage: :url_validation, code: :dns_resolution_timeout}} =
             SafeURL.validate("https://slow.example/oauth2/default")
  end

  test "creates authorization-code requests with state, nonce, and S256 PKCE", context do
    assert {:ok, authorization_uri} =
             Oidcc.authorization_uri(
               context.connection,
               context.transaction,
               context.transaction.redirect_uri,
               context.connection.client_secret
             )

    uri = URI.parse(authorization_uri)
    params = URI.decode_query(uri.query)

    assert URI.to_string(%{uri | query: nil}) == @authorization_endpoint
    assert params["client_id"] == "client-id"
    assert params["redirect_uri"] == context.transaction.redirect_uri
    assert params["response_type"] == "code"
    assert params["scope"] == "openid email"
    assert params["state"] == "state"
    assert params["nonce"] == "nonce"
    assert params["code_challenge_method"] == "S256"
    refute params["code_challenge"] == context.transaction.code_verifier
  end

  test "passes an ephemeral login hint only when one is present", context do
    transaction = %{context.transaction | login_hint: "person@example.com"}

    assert {:ok, authorization_uri} =
             Oidcc.authorization_uri(
               context.connection,
               transaction,
               transaction.redirect_uri,
               context.connection.client_secret
             )

    assert URI.decode_query(URI.parse(authorization_uri).query)["login_hint"] ==
             "person@example.com"

    assert {:ok, authorization_uri} =
             Oidcc.authorization_uri(
               context.connection,
               context.transaction,
               context.transaction.redirect_uri,
               context.connection.client_secret
             )

    refute URI.decode_query(URI.parse(authorization_uri).query)["login_hint"]
  end

  test "does not hide authorization setup exceptions", context do
    connection = %{context.connection | client_id: nil}

    assert_raise FunctionClauseError, fn ->
      Oidcc.authorization_uri(
        connection,
        context.transaction,
        context.transaction.redirect_uri,
        context.connection.client_secret
      )
    end
  end

  test "exchanges a code and validates signed ID-token claims", context do
    now = DateTime.utc_now() |> DateTime.to_unix()

    id_token =
      context.key
      |> JOSE.JWT.sign(%{"alg" => "RS256", "kid" => "key-1"}, %{
        "iss" => @issuer,
        "sub" => "00u123",
        "aud" => "client-id",
        "azp" => "client-id",
        "nonce" => context.transaction.nonce,
        "iat" => now,
        "exp" => now + 300,
        "email" => "member@example.com"
      })
      |> JOSE.JWS.compact()
      |> elem(1)

    expect(Hexpm.HTTP.Mock, :post, fn url, headers, body, opts ->
      assert url == @token_endpoint
      assert {"authorization", authorization} = List.keyfind(headers, "authorization", 0)
      assert String.starts_with?(authorization, "Basic ")

      assert List.keyfind(headers, "content-type", 0) ==
               {"content-type", "application/x-www-form-urlencoded"}

      params = URI.decode_query(body)
      refute Map.has_key?(params, "client_secret")
      assert params["grant_type"] == "authorization_code"
      assert params["code"] == "authorization-code"
      assert params["code_verifier"] == context.transaction.code_verifier
      assert params["redirect_uri"] == context.transaction.redirect_uri
      assert opts[:decode_body] == false

      {:ok, 200, [{"content-type", "application/json"}], JSON.encode!(%{"id_token" => id_token})}
    end)

    assert {:ok, claims} =
             Oidcc.exchange_code(
               context.connection,
               context.transaction,
               "authorization-code",
               context.transaction.redirect_uri,
               context.connection.client_secret
             )

    assert claims.issuer == @issuer
    assert claims.subject == "00u123"
    assert claims.email == "member@example.com"
    refute Map.has_key?(claims, :id_token)
    refute Map.has_key?(claims, :access_token)
  end

  test "uses stable Entra subjects and never substitutes guest usernames for a missing email",
       context do
    entra_issuer =
      "https://login.microsoftonline.com/11111111-2222-3333-4444-555555555555/v2.0"

    connection = %{
      context.connection
      | issuer: entra_issuer,
        discovery_document: Map.put(context.connection.discovery_document, "issuer", entra_issuer)
    }

    guest_token =
      signed_id_token(context.key, "key-1", context.transaction, %{
        "iss" => entra_issuer,
        "sub" => "stable-guest-subject",
        "email" => "guest_external.example#EXT#@tenant.onmicrosoft.com",
        "preferred_username" => "guest@example.net",
        "tid" => "11111111-2222-3333-4444-555555555555"
      })

    expect_token_response(guest_token)

    assert {:ok,
            %{
              subject: "stable-guest-subject",
              email: "guest_external.example#EXT#@tenant.onmicrosoft.com"
            }} =
             Oidcc.exchange_code(
               connection,
               context.transaction,
               "authorization-code",
               context.transaction.redirect_uri,
               connection.client_secret
             )

    missing_email_token =
      signed_id_token_without_email(context.key, "key-1", context.transaction, %{
        "iss" => entra_issuer,
        "sub" => "stable-guest-subject",
        "preferred_username" => "renamed-guest@example.net",
        "upn" => "renamed-guest@example.net"
      })

    expect_token_response(missing_email_token)

    assert {:ok, %{subject: "stable-guest-subject", email: nil}} =
             Oidcc.exchange_code(
               connection,
               context.transaction,
               "authorization-code",
               context.transaction.redirect_uri,
               connection.client_secret
             )
  end

  test "refreshes JWKS once for an unknown key ID and keeps strict validation", context do
    replacement_key = JOSE.JWK.generate_key({:rsa, 1_024})
    {_, public_key} = JOSE.JWK.to_public_map(replacement_key)
    refreshed_jwks = %{"keys" => [Map.put(public_key, "kid", "key-2")]}

    id_token = signed_id_token(replacement_key, "key-2", context.transaction)
    expect_token_response(id_token)
    expect_json_get(@jwks_uri, refreshed_jwks)

    assert {:ok, claims} =
             Oidcc.exchange_code(
               context.connection,
               context.transaction,
               "authorization-code",
               context.transaction.redirect_uri,
               context.connection.client_secret
             )

    assert claims.subject == "00u123"
    assert claims.jwks_document == refreshed_jwks
    assert %DateTime{} = claims.jwks_expires_at
  end

  test "reports a token endpoint that keeps asking for a DPoP nonce as a refusal", context do
    # oidcc turns any non-2xx carrying this header into use_dpop_nonce and
    # retries once, so both attempts have to answer the same way.
    expect(Hexpm.HTTP.Mock, :post, 2, fn _url, _headers, _body, _opts ->
      {:ok, 400, [{"content-type", "application/json"}, {"dpop-nonce", "nonce-value"}],
       JSON.encode!(%{"error" => "invalid_grant"})}
    end)

    assert {:error, %Error{stage: :token, code: :token_endpoint_rejected_request}} =
             Oidcc.exchange_code(
               context.connection,
               context.transaction,
               "authorization-code",
               context.transaction.redirect_uri,
               context.connection.client_secret
             )
  end

  test "separates an unreachable token endpoint from an invalid ID token", context do
    expect(Hexpm.HTTP.Mock, :post, fn _url, _headers, _body, _opts ->
      {:error, %Mint.TransportError{reason: :timeout}}
    end)

    assert {:error, %Error{stage: :token, code: :token_endpoint_unavailable}} =
             Oidcc.exchange_code(
               context.connection,
               context.transaction,
               "authorization-code",
               context.transaction.redirect_uri,
               context.connection.client_secret
             )
  end

  test "rejects a token response that the provider refused", context do
    expect(Hexpm.HTTP.Mock, :post, fn _url, _headers, _body, _opts ->
      {:ok, 400, [{"content-type", "application/json"}],
       JSON.encode!(%{"error" => "invalid_grant"})}
    end)

    assert {:error, %Error{stage: :token, code: :token_endpoint_rejected_request}} =
             Oidcc.exchange_code(
               context.connection,
               context.transaction,
               "authorization-code",
               context.transaction.redirect_uri,
               context.connection.client_secret
             )
  end

  test "rejects a token response without an ID token", context do
    expect(Hexpm.HTTP.Mock, :post, fn _url, _headers, _body, _opts ->
      {:ok, 200, [{"content-type", "application/json"}],
       JSON.encode!(%{"access_token" => "opaque", "token_type" => "Bearer"})}
    end)

    assert {:error, %Error{stage: :token, code: :id_token_missing}} =
             Oidcc.exchange_code(
               context.connection,
               context.transaction,
               "authorization-code",
               context.transaction.redirect_uri,
               context.connection.client_secret
             )
  end

  test "rejects an ID token issued for another audience", context do
    id_token =
      signed_id_token(context.key, "key-1", context.transaction, %{
        "aud" => "another-client",
        "azp" => "another-client"
      })

    expect_token_response(id_token)

    assert {:error, %Error{stage: :token, code: :id_token_invalid}} =
             Oidcc.exchange_code(
               context.connection,
               context.transaction,
               "authorization-code",
               context.transaction.redirect_uri,
               context.connection.client_secret
             )
  end

  test "rejects an ID token with an authorized party for another client", context do
    id_token =
      signed_id_token(context.key, "key-1", context.transaction, %{
        "azp" => "another-client"
      })

    expect_token_response(id_token)

    assert {:error, %Error{stage: :token, code: :id_token_invalid}} =
             Oidcc.exchange_code(
               context.connection,
               context.transaction,
               "authorization-code",
               context.transaction.redirect_uri,
               context.connection.client_secret
             )
  end

  test "rejects invalid signatures, nonce, expiry, issuer, and issued-at values", context do
    now = DateTime.utc_now() |> DateTime.to_unix()

    cases = [
      {:wrong_nonce, context.key, %{"nonce" => "wrong"}},
      {:expired, context.key, %{"exp" => now - 300}},
      {:wrong_issuer, context.key, %{"iss" => "https://other.example.com"}},
      {:future_iat, context.key, %{"iat" => now + 600}},
      {:invalid_signature, JOSE.JWK.generate_key({:rsa, 1_024}), %{}}
    ]

    for {_name, key, overrides} <- cases do
      id_token = signed_id_token(key, "key-1", context.transaction, overrides)
      expect_token_response(id_token)

      assert {:error, %Error{}} =
               Oidcc.exchange_code(
                 context.connection,
                 context.transaction,
                 "authorization-code",
                 context.transaction.redirect_uri,
                 context.connection.client_secret
               )
    end
  end

  test "accepts a token issued before the transaction started", context do
    now = DateTime.utc_now() |> DateTime.to_unix()

    id_token =
      signed_id_token(context.key, "key-1", context.transaction, %{"iat" => now - 7_200})

    expect_token_response(id_token)

    assert {:ok, claims} =
             Oidcc.exchange_code(
               context.connection,
               context.transaction,
               "authorization-code",
               context.transaction.redirect_uri,
               context.connection.client_secret
             )

    assert claims.subject == "00u123"
  end

  test "rejects a token signed with a disallowed symmetric algorithm", context do
    now = DateTime.utc_now() |> DateTime.to_unix()
    key = JOSE.JWK.from_oct("a-secret-that-is-long-enough-for-hs256")

    id_token =
      key
      |> JOSE.JWT.sign(%{"alg" => "HS256", "kid" => "key-1"}, %{
        "iss" => @issuer,
        "sub" => "00u123",
        "aud" => "client-id",
        "azp" => "client-id",
        "nonce" => context.transaction.nonce,
        "iat" => now,
        "exp" => now + 300
      })
      |> JOSE.JWS.compact()
      |> elem(1)

    expect_token_response(id_token)

    assert {:error, %Error{stage: :token, code: :id_token_invalid}} =
             Oidcc.exchange_code(
               context.connection,
               context.transaction,
               "authorization-code",
               context.transaction.redirect_uri,
               context.connection.client_secret
             )
  end

  test "normalizes exceptions from malformed ID tokens at the OIDCC boundary", context do
    attach_token_validation_exception_handler()

    for id_token <- ["..", "a.b.c"] do
      expect_token_response(id_token)

      assert {:error, %Error{stage: :token, code: :id_token_invalid}} =
               Oidcc.exchange_code(
                 context.connection,
                 context.transaction,
                 "authorization-code",
                 context.transaction.redirect_uri,
                 context.connection.client_secret
               )

      assert_receive {:token_validation_exception, %{count: 1}, metadata}
      assert metadata.phase == :initial
      assert metadata.exception in [CaseClauseError, Jason.DecodeError]
      assert Map.keys(metadata) |> Enum.sort() == [:exception, :phase]
    end
  end

  test "normalizes exceptions after refreshing JWKS", context do
    attach_token_validation_exception_handler()

    replacement_key = JOSE.JWK.generate_key({:rsa, 1_024})
    {_, public_key} = JOSE.JWK.to_public_map(replacement_key)
    refreshed_jwks = %{"keys" => [Map.put(public_key, "kid", "key-2")]}

    id_token =
      signed_id_token(replacement_key, "key-2", context.transaction, %{"exp" => "not-an-integer"})

    expect_token_response(id_token)
    expect_json_get(@jwks_uri, refreshed_jwks)

    assert {:error, %Error{stage: :token, code: :id_token_invalid_after_jwks_refresh}} =
             Oidcc.exchange_code(
               context.connection,
               context.transaction,
               "authorization-code",
               context.transaction.redirect_uri,
               context.connection.client_secret
             )

    assert_receive {:token_validation_exception, %{count: 1},
                    %{exception: ArithmeticError, phase: :jwks_refresh}}
  end

  test "does not hide exceptions outside OIDCC token validation", context do
    expect(Hexpm.HTTP.Mock, :post, fn _url, _headers, _body, _opts ->
      raise "HTTP adapter failure"
    end)

    assert_raise RuntimeError, "HTTP adapter failure", fn ->
      Oidcc.exchange_code(
        context.connection,
        context.transaction,
        "authorization-code",
        context.transaction.redirect_uri,
        context.connection.client_secret
      )
    end
  end

  test "bounds provider subject and email claims before persistence", context do
    valid_subject = String.duplicate("s", 255)

    valid_token =
      signed_id_token(context.key, "key-1", context.transaction, %{"sub" => valid_subject})

    expect_token_response(valid_token)

    assert {:ok, %{subject: ^valid_subject}} =
             Oidcc.exchange_code(
               context.connection,
               context.transaction,
               "authorization-code",
               context.transaction.redirect_uri,
               context.connection.client_secret
             )

    for overrides <- [
          %{"sub" => String.duplicate("s", 256)},
          %{"sub" => "non-ascii-å"},
          %{"email" => String.duplicate("e", 321)}
        ] do
      token = signed_id_token(context.key, "key-1", context.transaction, overrides)
      expect_token_response(token)

      assert {:error, %Error{stage: :claims}} =
               Oidcc.exchange_code(
                 context.connection,
                 context.transaction,
                 "authorization-code",
                 context.transaction.redirect_uri,
                 context.connection.client_secret
               )
    end
  end

  test "exchange_code carries the provider session id through, dropping unusable ones",
       context do
    for {sid_claim, expected} <- [
          {"provider-session-1", "provider-session-1"},
          {String.duplicate("s", 4097), nil},
          {"", nil},
          {123, nil}
        ] do
      token = signed_id_token(context.key, "key-1", context.transaction, %{"sid" => sid_claim})
      expect_token_response(token)

      assert {:ok, %{sid: ^expected}} =
               Oidcc.exchange_code(
                 context.connection,
                 context.transaction,
                 "authorization-code",
                 context.transaction.redirect_uri,
                 context.connection.client_secret
               )
    end
  end

  describe "validate_logout_token/2" do
    test "accepts a conforming logout token", context do
      token = logout_token(context.key)

      assert {:ok, claims} = Oidcc.validate_logout_token(context.connection, token)
      assert claims.issuer == @issuer
      assert claims.subject == "00u123"
      assert claims.sid == "provider-session-1"
      assert claims.jwks_document == nil
    end

    test "accepts a token with no sid", context do
      token = logout_token(context.key, %{}, ["sid"])

      assert {:ok, %{sid: nil}} = Oidcc.validate_logout_token(context.connection, token)
    end

    test "rejects a sid-only token, since the subject is required", context do
      token = logout_token(context.key, %{}, ["sub"])

      assert {:error, %Error{stage: :logout_token, code: :required_claim_missing}} =
               Oidcc.validate_logout_token(context.connection, token)
    end

    test "rejects a token carrying a nonce", context do
      token = logout_token(context.key, %{"nonce" => "nonce"})

      assert {:error, %Error{stage: :logout_token, code: :nonce_present}} =
               Oidcc.validate_logout_token(context.connection, token)
    end

    test "rejects a token without the back-channel logout event", context do
      for events <- [
            :drop,
            %{},
            %{"http://schemas.openid.net/event/other" => %{}},
            %{"http://schemas.openid.net/event/backchannel-logout" => "not-an-object"}
          ] do
        token =
          case events do
            :drop -> logout_token(context.key, %{}, ["events"])
            events -> logout_token(context.key, %{"events" => events})
          end

        assert {:error, %Error{stage: :logout_token, code: :events_invalid}} =
                 Oidcc.validate_logout_token(context.connection, token)
      end
    end

    test "rejects an expired token", context do
      now = DateTime.utc_now() |> DateTime.to_unix()
      token = logout_token(context.key, %{"exp" => now - 10})

      assert {:error, %Error{stage: :logout_token, code: :expired}} =
               Oidcc.validate_logout_token(context.connection, token)
    end

    test "rejects a token issued too long ago even when it has not expired", context do
      now = DateTime.utc_now() |> DateTime.to_unix()
      token = logout_token(context.key, %{"iat" => now - 400, "exp" => now + 100})

      assert {:error, %Error{stage: :logout_token, code: :issued_at_too_old}} =
               Oidcc.validate_logout_token(context.connection, token)
    end

    test "rejects a token issued in the future", context do
      now = DateTime.utc_now() |> DateTime.to_unix()
      token = logout_token(context.key, %{"iat" => now + 120})

      assert {:error, %Error{stage: :logout_token, code: :issued_at_in_future}} =
               Oidcc.validate_logout_token(context.connection, token)
    end

    test "rejects a token for another audience or issuer", context do
      for overrides <- [%{"aud" => "someone-else"}, %{"iss" => "https://other.example.com"}] do
        token = logout_token(context.key, overrides)

        assert {:error, %Error{stage: :logout_token}} =
                 Oidcc.validate_logout_token(context.connection, token)
      end
    end

    test "rejects a token signed with an unknown key", context do
      other_key = JOSE.JWK.generate_key({:rsa, 1_024})
      token = logout_token(other_key)

      assert {:error, %Error{stage: :logout_token}} =
               Oidcc.validate_logout_token(context.connection, token)
    end

    test "rejects a symmetrically signed token", context do
      claims = default_logout_token_claims()

      token =
        %{"kty" => "oct", "k" => Base.url_encode64("client-secret", padding: false)}
        |> JOSE.JWK.from_map()
        |> JOSE.JWT.sign(%{"alg" => "HS256", "kid" => "key-1"}, claims)
        |> JOSE.JWS.compact()
        |> elem(1)

      assert {:error, %Error{stage: :logout_token}} =
               Oidcc.validate_logout_token(context.connection, token)
    end

    test "rejects a string that is not a token", context do
      assert {:error, %Error{stage: :logout_token}} =
               Oidcc.validate_logout_token(context.connection, "not-a-jwt")
    end

    test "refreshes the signing keys for an unknown kid and hands the document back",
         context do
      rotated_key = JOSE.JWK.generate_key({:rsa, 1_024})
      {_, rotated_public} = rotated_key |> JOSE.JWK.to_public_map()
      rotated_public = Map.put(rotated_public, "kid", "key-2")

      rotated_document = %{"keys" => [rotated_public]}
      expect_json_get(@jwks_uri, rotated_document, "max-age=300")

      token =
        rotated_key
        |> JOSE.JWT.sign(%{"alg" => "RS256", "kid" => "key-2"}, default_logout_token_claims())
        |> JOSE.JWS.compact()
        |> elem(1)

      assert {:ok, claims} = Oidcc.validate_logout_token(context.connection, token)
      assert claims.subject == "00u123"
      assert claims.jwks_document == rotated_document
      assert claims.jwks_expires_at
    end

    test "rejects an unusable sid rather than widening the logout", context do
      for sid <- [String.duplicate("s", 4097), 123, ""] do
        token = logout_token(context.key, %{"sid" => sid})

        assert {:error, %Error{stage: :logout_token, code: :sid_invalid}} =
                 Oidcc.validate_logout_token(context.connection, token)
      end
    end

    test "rejects a token without a token identifier", context do
      token = logout_token(context.key, %{}, ["jti"])

      assert {:error, %Error{stage: :logout_token, code: :jti_missing}} =
               Oidcc.validate_logout_token(context.connection, token)
    end

    test "does not fetch signing keys for an unknown kid when the caller forbids it",
         context do
      rotated_key = JOSE.JWK.generate_key({:rsa, 1_024})

      token =
        rotated_key
        |> JOSE.JWT.sign(%{"alg" => "RS256", "kid" => "key-2"}, default_logout_token_claims())
        |> JOSE.JWS.compact()
        |> elem(1)

      assert {:error, %Error{stage: :logout_token}} =
               Oidcc.validate_logout_token(context.connection, token, refresh_jwks: false)
    end
  end

  defp logout_token(key, overrides \\ %{}, drops \\ []) do
    claims =
      default_logout_token_claims()
      |> Map.merge(overrides)
      |> Map.drop(drops)

    sign_id_token(key, "key-1", claims)
  end

  defp default_logout_token_claims do
    now = DateTime.utc_now() |> DateTime.to_unix()

    %{
      "iss" => @issuer,
      "sub" => "00u123",
      "aud" => "client-id",
      "iat" => now,
      "exp" => now + 120,
      "jti" => "logout-jti",
      "events" => %{"http://schemas.openid.net/event/backchannel-logout" => %{}},
      "sid" => "provider-session-1"
    }
  end

  defp expect_json_get(url, document, cache_control \\ "max-age=600") do
    expect(Hexpm.HTTP.Mock, :get, fn received_url, headers, opts ->
      assert received_url == url
      assert headers == [{"accept", "application/json"}]
      assert opts[:decode_body] == false
      assert opts[:connect_address] == {1, 1, 1, 1}
      assert opts[:connect_hostname] == "1.1.1.1"
      assert opts[:receive_timeout] == 5_000
      assert opts[:request_timeout] == 5_000

      {:ok, 200, [{"content-type", "application/json"}, {"cache-control", cache_control}],
       JSON.encode!(document)}
    end)
  end

  defp expect_token_response(id_token) do
    expect(Hexpm.HTTP.Mock, :post, fn _url, _headers, _body, opts ->
      assert opts[:connect_address] == {1, 1, 1, 1}
      assert opts[:connect_hostname] == "1.1.1.1"
      {:ok, 200, [{"content-type", "application/json"}], JSON.encode!(%{"id_token" => id_token})}
    end)
  end

  defp attach_token_validation_exception_handler do
    handler_id = {__MODULE__, self(), make_ref()}
    test_pid = self()

    :ok =
      :telemetry.attach(
        handler_id,
        [:hexpm, :sso, :oidc, :token_validation_exception],
        fn _event, measurements, metadata, pid ->
          send(pid, {:token_validation_exception, measurements, metadata})
        end,
        test_pid
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)
  end

  defp signed_id_token(key, kid, transaction, overrides \\ %{}) do
    claims =
      transaction
      |> default_id_token_claims()
      |> Map.merge(overrides)

    sign_id_token(key, kid, claims)
  end

  defp signed_id_token_without_email(key, kid, transaction, overrides) do
    claims =
      transaction
      |> default_id_token_claims()
      |> Map.delete("email")
      |> Map.merge(overrides)

    sign_id_token(key, kid, claims)
  end

  defp default_id_token_claims(transaction) do
    now = DateTime.utc_now() |> DateTime.to_unix()

    %{
      "iss" => @issuer,
      "sub" => "00u123",
      "aud" => "client-id",
      "azp" => "client-id",
      "nonce" => transaction.nonce,
      "iat" => now,
      "exp" => now + 300,
      "email" => "member@example.com"
    }
  end

  defp sign_id_token(key, kid, claims) do
    key
    |> JOSE.JWT.sign(%{"alg" => "RS256", "kid" => kid}, claims)
    |> JOSE.JWS.compact()
    |> elem(1)
  end

  defp discovery_document do
    %{
      "issuer" => @issuer,
      "authorization_endpoint" => @authorization_endpoint,
      "token_endpoint" => @token_endpoint,
      "jwks_uri" => @jwks_uri,
      "scopes_supported" => ["openid", "email"],
      "response_types_supported" => ["code"],
      "subject_types_supported" => ["public"],
      "id_token_signing_alg_values_supported" => ["RS256"],
      "grant_types_supported" => ["authorization_code"],
      "token_endpoint_auth_methods_supported" => ["client_secret_basic"],
      "code_challenge_methods_supported" => ["S256"]
    }
  end

  defp restore_env(key, nil), do: Application.delete_env(:hexpm, key)
  defp restore_env(key, value), do: Application.put_env(:hexpm, key, value)
end
