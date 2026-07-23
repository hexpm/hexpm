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
      refute Map.has_key?(body, "client_secret")
      assert body["code"] == "authorization-code"
      assert body["code_verifier"] == context.transaction.code_verifier
      assert body["redirect_uri"] == context.transaction.redirect_uri
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
      {:old_iat, context.key, %{"iat" => now - 600}},
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
    now = DateTime.utc_now() |> DateTime.to_unix()

    claims =
      Map.merge(
        %{
          "iss" => @issuer,
          "sub" => "00u123",
          "aud" => "client-id",
          "azp" => "client-id",
          "nonce" => transaction.nonce,
          "iat" => now,
          "exp" => now + 300,
          "email" => "member@example.com"
        },
        overrides
      )

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
