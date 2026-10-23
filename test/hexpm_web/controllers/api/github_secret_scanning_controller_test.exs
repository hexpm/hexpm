defmodule HexpmWeb.API.GitHubSecretScanningControllerTest do
  use HexpmWeb.ConnCase, async: false
  use Oban.Testing, repo: Hexpm.RepoBase

  import Ecto.Query
  import Mox
  import Swoosh.TestAssertions

  alias Hexpm.Accounts.{Key, Keys, User}
  alias Hexpm.Emails.{OutboxEntry, OutboxWorker}
  alias Hexpm.GitHub.SecretScanning
  alias Hexpm.Repo
  alias Hexpm.WriteMode

  setup :verify_on_exit!

  # Generate a fresh ECDSA P256 key pair once for the test module.
  # Each test signs payloads with this private key and mocks the HTTP call
  # to return the corresponding public key.
  @key_id "test-key-id-abc123"

  setup do
    {pem_pub, ec_priv} = SecretScanning.generate_test_keypair()
    conn = build_conn()

    stub_github_keys = fn ->
      Mox.expect(Hexpm.HTTP.Mock, :get, fn url, _headers ->
        assert String.contains?(url, "secret_scanning")

        {:ok, 200, [],
         %{
           "public_keys" => [
             %{"key_identifier" => @key_id, "key" => pem_pub, "is_current" => true}
           ]
         }}
      end)
    end

    user = insert(:user)

    %{
      conn: conn,
      user: user,
      pem_pub: pem_pub,
      ec_priv: ec_priv,
      stub_github_keys: stub_github_keys
    }
  end

  defp alert(key) do
    %{
      "token" => key.user_secret,
      "type" => "hexpm_api_token",
      "url" => "https://github.com/example/repo",
      "source" => "commit"
    }
  end

  defp deliver_leak_notice(key) do
    entry = Repo.get_by!(OutboxEntry, group_key: "key-leaked:#{key.id}")
    assert :ok = perform_job(OutboxWorker, %{outbox_entry_id: entry.id})
    entry
  end

  defp post_alert(conn, body, ec_priv, key_id \\ @key_id) do
    raw = Jason.encode!(body)
    sig = SecretScanning.sign_payload(raw, ec_priv)

    conn
    |> put_req_header("content-type", "application/json")
    |> put_req_header("github-public-key-identifier", key_id)
    |> put_req_header("github-public-key-signature", sig)
    |> dispatch(HexpmWeb.Endpoint, :post, "/api/github/secret-scanning", raw)
  end

  describe "POST /api/github/secret-scanning" do
    test "returns 200, revokes key, and responds with true_positive label", %{
      conn: conn,
      user: user,
      ec_priv: ec_priv,
      stub_github_keys: stub
    } do
      stub.()
      {:ok, %{key: key}} = Keys.create(user, %{"name" => "leaked"}, audit: audit_data(user))

      conn =
        post_alert(
          conn,
          [
            %{
              "token" => key.user_secret,
              "type" => "hexpm_api_token",
              "url" => "https://github.com/example/repo",
              "source" => "commit"
            }
          ],
          ec_priv
        )

      assert [%{"label" => "true_positive", "token_type" => "hexpm_api_token"}] =
               json_response(conn, 200)

      revoked = Repo.get!(Key, key.id)
      assert revoked.revoke_at != nil
      assert DateTime.compare(revoked.revoke_at, DateTime.utc_now()) != :gt
    end

    test "sends key_leaked email to the key owner", %{
      conn: conn,
      user: user,
      ec_priv: ec_priv,
      stub_github_keys: stub
    } do
      stub.()
      {:ok, %{key: key}} = Keys.create(user, %{"name" => "ci-key"}, audit: audit_data(user))

      # Keys.create now sends an api_key_created security notification;
      # consume it so it doesn't shadow the key_leaked assertion below.
      assert_email_sent(subject: ~r/new API key.*created/i)

      post_alert(
        conn,
        [
          %{
            "token" => key.user_secret,
            "type" => "hexpm_api_token",
            "url" => "https://github.com/example/repo",
            "source" => "commit"
          }
        ],
        ec_priv
      )

      assert_no_email_sent()
      deliver_leak_notice(key)

      assert_email_sent(
        subject: ~r/ci-key.*revoked/i,
        html_body: ~r|https://github\.com/example/repo|,
        text_body: ~r|https://github\.com/example/repo|
      )
    end

    test "returns false_positive label for an unknown token", %{
      conn: conn,
      ec_priv: ec_priv,
      stub_github_keys: stub
    } do
      stub.()
      fake_token = "hex_" <> String.duplicate("a", 40)

      conn =
        post_alert(
          conn,
          [
            %{
              "token" => fake_token,
              "type" => "hexpm_api_token",
              "url" => "",
              "source" => "content"
            }
          ],
          ec_priv
        )

      assert [%{"label" => "false_positive", "token_type" => "hexpm_api_token"}] =
               json_response(conn, 200)
    end

    test "processes multiple alerts and returns one result per token", %{
      conn: conn,
      user: user,
      ec_priv: ec_priv,
      stub_github_keys: stub
    } do
      stub.()
      {:ok, %{key: key1}} = Keys.create(user, %{"name" => "key1"}, audit: audit_data(user))
      {:ok, %{key: key2}} = Keys.create(user, %{"name" => "key2"}, audit: audit_data(user))

      alerts = [
        %{
          "token" => key1.user_secret,
          "type" => "hexpm_api_token",
          "url" => "",
          "source" => "content"
        },
        %{
          "token" => key2.user_secret,
          "type" => "hexpm_api_token",
          "url" => "",
          "source" => "content"
        }
      ]

      conn = post_alert(conn, alerts, ec_priv)

      assert [
               %{"label" => "true_positive"},
               %{"label" => "true_positive"}
             ] = json_response(conn, 200)

      assert Repo.get!(Key, key1.id).revoke_at != nil
      assert Repo.get!(Key, key2.id).revoke_at != nil
    end

    test "returns 403 when signature is invalid", %{conn: conn, user: user} do
      {:ok, %{key: key}} = Keys.create(user, %{"name" => "leaked"}, audit: audit_data(user))

      raw =
        Jason.encode!([
          %{
            "token" => key.user_secret,
            "type" => "hexpm_api_token",
            "url" => "",
            "source" => "content"
          }
        ])

      Mox.expect(Hexpm.HTTP.Mock, :get, fn _url, _headers ->
        # Return a different (wrong) key so the signature check fails
        {pem_wrong, _priv} = SecretScanning.generate_test_keypair()

        {:ok, 200, [],
         %{
           "public_keys" => [
             %{"key_identifier" => @key_id, "key" => pem_wrong, "is_current" => true}
           ]
         }}
      end)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("github-public-key-identifier", @key_id)
        |> put_req_header("github-public-key-signature", "bm90YXZhbGlkc2ln")
        |> dispatch(HexpmWeb.Endpoint, :post, "/api/github/secret-scanning", raw)

      assert conn.status == 403
      # Key must NOT have been revoked
      assert Repo.get!(Key, key.id).revoke_at == nil
    end

    test "returns 403 when signature is for a different body", %{
      conn: conn,
      user: user,
      ec_priv: ec_priv,
      stub_github_keys: stub
    } do
      stub.()
      {:ok, %{key: key}} = Keys.create(user, %{"name" => "safe"}, audit: audit_data(user))

      # Sign a different payload, then send it with the original body
      decoy =
        Jason.encode!([
          %{
            "token" => "hex_" <> String.duplicate("f", 40),
            "type" => "hexpm_api_token",
            "url" => "",
            "source" => "content"
          }
        ])

      sig = SecretScanning.sign_payload(decoy, ec_priv)

      real_body =
        Jason.encode!([
          %{
            "token" => key.user_secret,
            "type" => "hexpm_api_token",
            "url" => "",
            "source" => "content"
          }
        ])

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("github-public-key-identifier", @key_id)
        |> put_req_header("github-public-key-signature", sig)
        |> dispatch(HexpmWeb.Endpoint, :post, "/api/github/secret-scanning", real_body)

      assert conn.status == 403
      assert Repo.get!(Key, key.id).revoke_at == nil
    end

    test "returns 400 for empty body", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("github-public-key-identifier", @key_id)
        |> put_req_header("github-public-key-signature", "anysig")
        |> dispatch(HexpmWeb.Endpoint, :post, "/api/github/secret-scanning", "")

      assert conn.status == 400
    end

    test "returns 403 when GitHub public key fetch fails", %{
      conn: conn,
      user: user,
      ec_priv: ec_priv
    } do
      {:ok, %{key: key}} = Keys.create(user, %{"name" => "safe"}, audit: audit_data(user))

      raw =
        Jason.encode!([
          %{
            "token" => key.user_secret,
            "type" => "hexpm_api_token",
            "url" => "",
            "source" => "content"
          }
        ])

      sig = SecretScanning.sign_payload(raw, ec_priv)

      Mox.expect(Hexpm.HTTP.Mock, :get, fn _url, _headers ->
        {:error, %Mint.TransportError{reason: :econnrefused}}
      end)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("github-public-key-identifier", @key_id)
        |> put_req_header("github-public-key-signature", sig)
        |> dispatch(HexpmWeb.Endpoint, :post, "/api/github/secret-scanning", raw)

      assert conn.status == 403
      assert Repo.get!(Key, key.id).revoke_at == nil
    end

    test "emails the administrators about a leaked organization key", %{
      conn: conn,
      ec_priv: ec_priv,
      stub_github_keys: stub
    } do
      stub.()
      organization = insert(:organization)
      admin = insert(:user)
      insert(:organization_user, organization: organization, user: admin, role: "admin")
      insert(:organization_user, organization: organization, user: insert(:user), role: "read")

      {:ok, %{key: key}} =
        Keys.create(organization, %{"name" => "org-key"}, audit: audit_data(organization))

      # Consume the api_key_created security notification sent by Keys.create
      # so the assertion below only covers the revocation flow.
      assert_email_sent(subject: ~r/new API key.*created/i)

      conn = post_alert(conn, [alert(key)], ec_priv)

      assert [%{"label" => "true_positive"}] = json_response(conn, 200)
      assert Repo.get!(Key, key.id).revoke_at != nil

      assert deliver_leak_notice(key).recipients == [User.email(admin, :primary)]

      assert_email_sent(
        subject: ~r/org-key.*revoked/i,
        text_body: ~r|/dashboard/orgs/#{organization.name}|
      )
    end

    test "revokes the OAuth tokens the leaked key was exchanged for", %{
      conn: conn,
      user: user,
      ec_priv: ec_priv,
      stub_github_keys: stub
    } do
      stub.()
      {:ok, %{key: key}} = Keys.create(user, %{"name" => "exchanged"}, audit: audit_data(user))
      client = insert(:oauth_client)

      %{"access_token" => access_token} =
        build_conn()
        |> post(~p"/api/oauth/token", %{
          "grant_type" => "client_credentials",
          "client_id" => client.client_id,
          "client_secret" => key.user_secret,
          "scope" => "api:read"
        })
        |> json_response(200)

      build_conn()
      |> put_req_header("authorization", "Bearer #{access_token}")
      |> get(~p"/api/users/me")
      |> json_response(200)

      assert [%{"label" => "true_positive"}] =
               conn |> post_alert([alert(key)], ec_priv) |> json_response(200)

      build_conn()
      |> put_req_header("authorization", "Bearer #{access_token}")
      |> get(~p"/api/users/me")
      |> json_response(401)
    end

    test "queues the notices so delivery can't fail the batch, one per key", %{
      conn: conn,
      user: user,
      ec_priv: ec_priv,
      stub_github_keys: stub
    } do
      stub.()
      {:ok, %{key: key1}} = Keys.create(user, %{"name" => "key1"}, audit: audit_data(user))
      {:ok, %{key: key2}} = Keys.create(user, %{"name" => "key2"}, audit: audit_data(user))
      assert_email_sent(subject: ~r/new API key.*created/i)
      assert_email_sent(subject: ~r/new API key.*created/i)

      conn = post_alert(conn, [alert(key1), alert(key2), alert(key1)], ec_priv)

      assert [
               %{"label" => "true_positive"},
               %{"label" => "true_positive"},
               %{"label" => "true_positive"}
             ] = json_response(conn, 200)

      assert_no_email_sent()

      assert Repo.aggregate(from(e in OutboxEntry, where: e.category == "key.leaked"), :count) ==
               2

      deliver_leak_notice(key1)
      deliver_leak_notice(key2)
    end

    test "refuses alerts while the site is read-only", %{
      conn: conn,
      user: user,
      ec_priv: ec_priv
    } do
      {:ok, %{key: key}} = Keys.create(user, %{"name" => "held"}, audit: audit_data(user))
      WriteMode.configure!(true)
      on_exit(fn -> WriteMode.configure!(false) end)

      conn = post_alert(conn, [alert(key)], ec_priv)

      assert conn.status == 503
      assert Repo.get!(Key, key.id).revoke_at == nil
    end

    test "refreshes public keys when an unknown key_identifier is received", %{
      conn: conn,
      user: user,
      pem_pub: pem_pub,
      ec_priv: ec_priv
    } do
      {:ok, %{key: key}} = Keys.create(user, %{"name" => "rotated"}, audit: audit_data(user))
      rotated_key_id = "rotated-key-id-xyz"

      Mox.expect(Hexpm.HTTP.Mock, :get, 2, fn _url, _headers ->
        # First call returns stale keys without the rotated identifier.
        # After cache invalidation, the second call returns the new identifier.
        if Process.get(:got_first_call) do
          {:ok, 200, [],
           %{
             "public_keys" => [
               %{"key_identifier" => rotated_key_id, "key" => pem_pub, "is_current" => true}
             ]
           }}
        else
          Process.put(:got_first_call, true)

          {:ok, 200, [],
           %{
             "public_keys" => [
               %{"key_identifier" => "stale-key-id", "key" => pem_pub, "is_current" => false}
             ]
           }}
        end
      end)

      conn =
        post_alert(
          conn,
          [
            %{
              "token" => key.user_secret,
              "type" => "hexpm_api_token",
              "url" => "",
              "source" => "content"
            }
          ],
          ec_priv,
          rotated_key_id
        )

      assert [%{"label" => "true_positive"}] = json_response(conn, 200)
      assert Repo.get!(Key, key.id).revoke_at != nil
    end

    test "does not retry the key fetch on a tampered signature with a known key_id", %{
      conn: conn,
      user: user,
      ec_priv: ec_priv,
      stub_github_keys: stub
    } do
      # Only one stub allowed; a second HTTP call would fail Mox verification.
      stub.()

      {:ok, %{key: key}} = Keys.create(user, %{"name" => "tampered"}, audit: audit_data(user))

      raw =
        Jason.encode!([
          %{
            "token" => key.user_secret,
            "type" => "hexpm_api_token",
            "url" => "",
            "source" => "content"
          }
        ])

      # Sign a different payload so verify fails for the known key.
      decoy_sig = SecretScanning.sign_payload("not the body", ec_priv)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("github-public-key-identifier", @key_id)
        |> put_req_header("github-public-key-signature", decoy_sig)
        |> dispatch(HexpmWeb.Endpoint, :post, "/api/github/secret-scanning", raw)

      assert conn.status == 403
      assert Repo.get!(Key, key.id).revoke_at == nil
    end

    test "labels a key revoked before the alert true_positive without a new notice", %{
      conn: conn,
      user: user,
      ec_priv: ec_priv,
      stub_github_keys: stub
    } do
      stub.()
      {:ok, %{key: key}} = Keys.create(user, %{"name" => "old"}, audit: audit_data(user))

      # Consume the api_key_created security notification sent by Keys.create
      # so the assertion below only covers the revocation flow.
      assert_email_sent(subject: ~r/new API key.*created/i)

      # Stamp the key as revoked a day ago using raw SQL to avoid any timing ambiguity
      # between Elixir's DateTime.utc_now() and PostgreSQL's NOW() in the sandbox.
      Repo.update_all(
        from(k in Key, where: k.id == ^key.id),
        set: [revoke_at: ~U[2020-01-01 00:00:00Z]]
      )

      # GitHub alert arrives for the already-revoked key
      conn =
        post_alert(
          conn,
          [
            %{
              "token" => key.user_secret,
              "type" => "hexpm_api_token",
              "url" => "",
              "source" => "content"
            }
          ],
          ec_priv
        )

      assert [%{"label" => "true_positive"}] = json_response(conn, 200)
      refute Repo.exists?(from(e in OutboxEntry, where: e.category == "key.leaked"))
      assert_no_email_sent()
    end
  end

  describe "POST /api/github/secret-scanning with the public key cache" do
    # The cache fetches the keys from a process of its own.
    setup :set_mox_global

    setup do
      Hexpm.Cache.start()
      ttl = Application.get_env(:hexpm, :github_key_cache_ttl)
      Application.put_env(:hexpm, :github_key_cache_ttl, 300)

      on_exit(fn ->
        Application.put_env(:hexpm, :github_key_cache_ttl, ttl)
        :ets.whereis(Hexpm.Cache) != :undefined && :ets.delete(Hexpm.Cache)
      end)
    end

    test "does not cache a failed key fetch", %{
      conn: conn,
      user: user,
      ec_priv: ec_priv,
      stub_github_keys: stub
    } do
      {:ok, %{key: key}} = Keys.create(user, %{"name" => "leaked"}, audit: audit_data(user))

      Mox.expect(Hexpm.HTTP.Mock, :get, fn _url, _headers ->
        {:error, %Mint.TransportError{reason: :timeout}}
      end)

      assert post_alert(conn, [alert(key)], ec_priv).status == 403

      stub.()

      assert [%{"label" => "true_positive"}] =
               build_conn() |> post_alert([alert(key)], ec_priv) |> json_response(200)
    end

    test "refetches for an unknown key id at most once a minute", %{
      conn: conn,
      user: user,
      pem_pub: pem_pub,
      ec_priv: ec_priv,
      stub_github_keys: stub
    } do
      {:ok, %{key: key1}} = Keys.create(user, %{"name" => "key1"}, audit: audit_data(user))
      {:ok, %{key: key2}} = Keys.create(user, %{"name" => "key2"}, audit: audit_data(user))
      stub.()

      assert [%{"label" => "true_positive"}] =
               conn |> post_alert([alert(key1)], ec_priv) |> json_response(200)

      for n <- 1..3 do
        assert build_conn()
               |> post_alert([alert(key2)], ec_priv, "unknown-#{n}")
               |> Map.get(:status) ==
                 403
      end

      assert Repo.get!(Key, key2.id).revoke_at == nil

      :ets.update_element(
        Hexpm.Cache,
        :github_secret_scanning_keys,
        {4, System.monotonic_time(:second) - 61}
      )

      Mox.expect(Hexpm.HTTP.Mock, :get, fn _url, _headers ->
        {:ok, 200, [], %{"public_keys" => [%{"key_identifier" => "rotated", "key" => pem_pub}]}}
      end)

      assert [%{"label" => "true_positive"}] =
               build_conn() |> post_alert([alert(key2)], ec_priv, "rotated") |> json_response(200)
    end

    test "keeps the cached keys when a refetch fails", %{
      conn: conn,
      user: user,
      ec_priv: ec_priv,
      stub_github_keys: stub
    } do
      {:ok, %{key: key1}} = Keys.create(user, %{"name" => "key1"}, audit: audit_data(user))
      {:ok, %{key: key2}} = Keys.create(user, %{"name" => "key2"}, audit: audit_data(user))
      stub.()

      assert [%{"label" => "true_positive"}] =
               conn |> post_alert([alert(key1)], ec_priv) |> json_response(200)

      :ets.update_element(
        Hexpm.Cache,
        :github_secret_scanning_keys,
        {4, System.monotonic_time(:second) - 61}
      )

      Mox.expect(Hexpm.HTTP.Mock, :get, fn _url, _headers -> {:ok, 503, [], %{}} end)

      assert build_conn() |> post_alert([alert(key2)], ec_priv, "unknown") |> Map.get(:status) ==
               403

      assert [%{"label" => "true_positive"}] =
               build_conn() |> post_alert([alert(key2)], ec_priv) |> json_response(200)
    end
  end
end
