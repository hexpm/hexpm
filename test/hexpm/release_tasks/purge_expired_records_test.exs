defmodule Hexpm.ReleaseTasks.PurgeExpiredRecordsTest do
  use Hexpm.DataCase
  use Oban.Testing, repo: Hexpm.RepoBase

  alias Hexpm.CronMonitor.SentryMock
  alias Hexpm.ReleaseTasks.PurgeExpiredRecords

  setup :verify_on_exit!

  test "runs as a monitored worker" do
    app_env(:hexpm, :sentry_impl, SentryMock)

    expect(SentryMock, :capture_check_in, fn opts ->
      assert opts[:status] == :in_progress
      assert opts[:monitor_slug] == "hexpm-purge-expired-records"

      assert opts[:monitor_config] == [
               schedule: [type: :crontab, value: "0 2 * * *"],
               timezone: "Etc/UTC"
             ]

      {:ok, "check-in-id"}
    end)

    expect(SentryMock, :capture_check_in, fn opts ->
      assert opts == [
               check_in_id: "check-in-id",
               status: :ok,
               monitor_slug: "hexpm-purge-expired-records"
             ]

      :ignored
    end)

    assert :ok = perform_job(PurgeExpiredRecords, %{})
  end

  test "rejects arguments because purging always processes all eligible records" do
    assert {:cancel, {:invalid_args, %{"date" => "2026-07-20"}}} =
             perform_job(PurgeExpiredRecords, %{"date" => "2026-07-20"})
  end

  defp seconds_ago(seconds) do
    DateTime.add(DateTime.utc_now(), -seconds, :second)
  end

  defp seconds_from_now(seconds) do
    DateTime.add(DateTime.utc_now(), seconds, :second)
  end

  defp truncated_seconds_ago(seconds) do
    seconds_ago(seconds) |> DateTime.truncate(:second)
  end

  defp truncated_seconds_from_now(seconds) do
    seconds_from_now(seconds) |> DateTime.truncate(:second)
  end

  defp days_ago(days), do: seconds_ago(days * 86400)

  describe "purge authorization codes" do
    test "deletes any expired code" do
      user = insert(:user)
      client = insert(:oauth_client)

      expired =
        Repo.insert!(%Hexpm.OAuth.AuthorizationCode{
          code: "expired-code",
          redirect_uri: "https://example.com/callback",
          scopes: ["api"],
          expires_at: truncated_seconds_ago(60),
          code_challenge: "challenge",
          code_challenge_method: "S256",
          user_id: user.id,
          client_id: client.client_id
        })

      active =
        Repo.insert!(%Hexpm.OAuth.AuthorizationCode{
          code: "active-code",
          redirect_uri: "https://example.com/callback",
          scopes: ["api"],
          expires_at: truncated_seconds_from_now(600),
          code_challenge: "challenge2",
          code_challenge_method: "S256",
          user_id: user.id,
          client_id: client.client_id
        })

      PurgeExpiredRecords.run()

      refute Repo.get(Hexpm.OAuth.AuthorizationCode, expired.id)
      assert Repo.get(Hexpm.OAuth.AuthorizationCode, active.id)
    end
  end

  describe "purge device codes" do
    test "deletes any expired code" do
      client = insert(:oauth_client)

      expired =
        Repo.insert!(%Hexpm.OAuth.DeviceCode{
          device_code: "expired-device",
          user_code: "EXPR1234",
          verification_uri: "https://hex.pm/device",
          expires_at: seconds_ago(60),
          client_id: client.client_id
        })

      active =
        Repo.insert!(%Hexpm.OAuth.DeviceCode{
          device_code: "active-device",
          user_code: "ACTV5678",
          verification_uri: "https://hex.pm/device",
          expires_at: seconds_from_now(600),
          client_id: client.client_id
        })

      PurgeExpiredRecords.run()

      refute Repo.get(Hexpm.OAuth.DeviceCode, expired.id)
      assert Repo.get(Hexpm.OAuth.DeviceCode, active.id)
    end
  end

  describe "purge oauth tokens" do
    test "deletes any expired token" do
      user = insert(:user)
      client = insert(:oauth_client)

      expired =
        Repo.insert!(%Hexpm.OAuth.Token{
          jti: "expired-jti",
          token_type: "bearer",
          scopes: ["api"],
          expires_at: truncated_seconds_ago(60),
          grant_type: "authorization_code",
          user_id: user.id,
          client_id: client.client_id
        })

      active =
        Repo.insert!(%Hexpm.OAuth.Token{
          jti: "active-jti",
          token_type: "bearer",
          scopes: ["api"],
          expires_at: truncated_seconds_from_now(86400),
          grant_type: "authorization_code",
          user_id: user.id,
          client_id: client.client_id
        })

      PurgeExpiredRecords.run()

      refute Repo.get(Hexpm.OAuth.Token, expired.id)
      assert Repo.get(Hexpm.OAuth.Token, active.id)
    end

    test "keeps expired tokens whose refresh token is still valid" do
      user = insert(:user)
      client = insert(:oauth_client)

      token =
        Repo.insert!(%Hexpm.OAuth.Token{
          jti: "expired-access-jti",
          refresh_jti: "live-refresh-jti",
          token_type: "bearer",
          scopes: ["api"],
          expires_at: truncated_seconds_ago(60),
          refresh_token_expires_at: truncated_seconds_from_now(86400),
          grant_type: "authorization_code",
          user_id: user.id,
          client_id: client.client_id
        })

      PurgeExpiredRecords.run()

      assert Repo.get(Hexpm.OAuth.Token, token.id)
    end

    test "deletes tokens whose refresh token has also expired" do
      user = insert(:user)
      client = insert(:oauth_client)

      token =
        Repo.insert!(%Hexpm.OAuth.Token{
          jti: "expired-access-jti",
          refresh_jti: "expired-refresh-jti",
          token_type: "bearer",
          scopes: ["api"],
          expires_at: truncated_seconds_ago(86400),
          refresh_token_expires_at: truncated_seconds_ago(60),
          grant_type: "authorization_code",
          user_id: user.id,
          client_id: client.client_id
        })

      PurgeExpiredRecords.run()

      refute Repo.get(Hexpm.OAuth.Token, token.id)
    end

    test "deletes any revoked token" do
      user = insert(:user)
      client = insert(:oauth_client)

      revoked =
        Repo.insert!(%Hexpm.OAuth.Token{
          jti: "revoked-jti",
          token_type: "bearer",
          scopes: ["api"],
          expires_at: truncated_seconds_from_now(86400),
          revoked_at: truncated_seconds_ago(60),
          grant_type: "authorization_code",
          user_id: user.id,
          client_id: client.client_id
        })

      PurgeExpiredRecords.run()

      refute Repo.get(Hexpm.OAuth.Token, revoked.id)
    end

    test "deletes revoked tokens whose refresh token has not expired" do
      user = insert(:user)
      client = insert(:oauth_client)

      revoked =
        Repo.insert!(%Hexpm.OAuth.Token{
          jti: "rotated-jti",
          refresh_jti: "rotated-refresh-jti",
          token_type: "bearer",
          scopes: ["api"],
          expires_at: truncated_seconds_ago(60),
          refresh_token_expires_at: truncated_seconds_from_now(86400),
          revoked_at: truncated_seconds_ago(60),
          grant_type: "refresh_token",
          user_id: user.id,
          client_id: client.client_id
        })

      PurgeExpiredRecords.run()

      refute Repo.get(Hexpm.OAuth.Token, revoked.id)
    end

    test "deletes records exceeding the batch size and keeps active ones" do
      user = insert(:user)
      client = insert(:oauth_client)

      expired =
        for i <- 1..5 do
          Repo.insert!(%Hexpm.OAuth.Token{
            jti: "expired-jti-#{i}",
            token_type: "bearer",
            scopes: ["api"],
            expires_at: truncated_seconds_ago(60),
            grant_type: "authorization_code",
            user_id: user.id,
            client_id: client.client_id
          })
        end

      active =
        Repo.insert!(%Hexpm.OAuth.Token{
          jti: "active-jti",
          token_type: "bearer",
          scopes: ["api"],
          expires_at: truncated_seconds_from_now(86400),
          grant_type: "authorization_code",
          user_id: user.id,
          client_id: client.client_id
        })

      PurgeExpiredRecords.run(batch_size: 2)
      PurgeExpiredRecords.run(batch_size: 2)

      for token <- expired do
        refute Repo.get(Hexpm.OAuth.Token, token.id)
      end

      assert Repo.get(Hexpm.OAuth.Token, active.id)
    end
  end

  describe "purge user sessions" do
    test "deletes any expired session" do
      user = insert(:user)

      expired =
        Repo.insert!(%Hexpm.UserSession{
          type: "browser",
          name: "expired session",
          session_token: :crypto.strong_rand_bytes(32),
          expires_at: seconds_ago(60),
          user_id: user.id
        })

      active =
        Repo.insert!(%Hexpm.UserSession{
          type: "browser",
          name: "active session",
          session_token: :crypto.strong_rand_bytes(32),
          expires_at: seconds_from_now(86400),
          user_id: user.id
        })

      PurgeExpiredRecords.run()

      refute Repo.get(Hexpm.UserSession, expired.id)
      assert Repo.get(Hexpm.UserSession, active.id)
    end

    test "deletes any revoked session" do
      user = insert(:user)

      revoked =
        Repo.insert!(%Hexpm.UserSession{
          type: "browser",
          name: "revoked session",
          session_token: :crypto.strong_rand_bytes(32),
          revoked_at: seconds_ago(60),
          user_id: user.id
        })

      PurgeExpiredRecords.run()

      refute Repo.get(Hexpm.UserSession, revoked.id)
    end

    test "keeps sessions with no expiry or revocation" do
      user = insert(:user)

      active =
        Repo.insert!(%Hexpm.UserSession{
          type: "browser",
          name: "active session",
          session_token: :crypto.strong_rand_bytes(32),
          user_id: user.id
        })

      PurgeExpiredRecords.run()

      assert Repo.get(Hexpm.UserSession, active.id)
    end
  end

  describe "purge password resets" do
    test "deletes resets older than 90 days" do
      user = insert(:user)

      old =
        Repo.insert!(%Hexpm.Accounts.PasswordReset{
          key: "old-key",
          primary_email: "old@example.com",
          user_id: user.id,
          inserted_at: days_ago(91)
        })

      recent =
        Repo.insert!(%Hexpm.Accounts.PasswordReset{
          key: "new-key",
          primary_email: "new@example.com",
          user_id: user.id
        })

      PurgeExpiredRecords.run()

      refute Repo.get(Hexpm.Accounts.PasswordReset, old.id)
      assert Repo.get(Hexpm.Accounts.PasswordReset, recent.id)
    end
  end

  describe "purge account deletion requests" do
    test "deletes requests older than 90 days" do
      user1 = insert(:user)
      user2 = insert(:user)

      old =
        Repo.insert!(%Hexpm.Accounts.AccountDeletionRequest{
          key: "old-key",
          primary_email: "old@example.com",
          user_id: user1.id,
          inserted_at: days_ago(91)
        })

      recent =
        Repo.insert!(%Hexpm.Accounts.AccountDeletionRequest{
          key: "new-key",
          primary_email: "new@example.com",
          user_id: user2.id
        })

      PurgeExpiredRecords.run()

      refute Repo.get(Hexpm.Accounts.AccountDeletionRequest, old.id)
      assert Repo.get(Hexpm.Accounts.AccountDeletionRequest, recent.id)
    end
  end

  describe "purge keys" do
    test "deletes keys revoked more than 90 days ago" do
      user = insert(:user)

      revoked = insert(:key, user: user, revoke_at: days_ago(91))
      recent_revoked = insert(:key, user: user, revoke_at: days_ago(60))
      active = insert(:key, user: user)

      PurgeExpiredRecords.run()

      refute Repo.get(Hexpm.Accounts.Key, revoked.id)
      assert Repo.get(Hexpm.Accounts.Key, recent_revoked.id)
      assert Repo.get(Hexpm.Accounts.Key, active.id)
    end
  end

  describe "purge organization SSO transactions" do
    test "deletes expired transactions and retains active ones" do
      connection =
        insert(:organization_sso_connection,
          organization: insert(:organization)
        )

      expired =
        Repo.insert!(%Hexpm.Accounts.SSO.Transaction{
          connection_id: connection.id,
          state_hash: :crypto.hash(:sha256, "expired-state"),
          kind: "login",
          secret_slot: "active",
          connection_version: connection.version,
          secret_version: connection.version,
          redirect_uri: "https://hex.pm/sso/callback",
          expires_at: days_ago(1)
        })

      active =
        Repo.insert!(%Hexpm.Accounts.SSO.Transaction{
          connection_id: connection.id,
          state_hash: :crypto.hash(:sha256, "active-state"),
          kind: "login",
          secret_slot: "active",
          connection_version: connection.version,
          secret_version: connection.version,
          redirect_uri: "https://hex.pm/sso/callback",
          expires_at: DateTime.add(DateTime.utc_now(), 600, :second)
        })

      PurgeExpiredRecords.run()

      refute Repo.get(Hexpm.Accounts.SSO.Transaction, expired.id)
      assert Repo.get(Hexpm.Accounts.SSO.Transaction, active.id)
    end
  end

  describe "purge organization SSO authorizations" do
    test "deletes expired verification codes and retains live ones" do
      user = insert(:user)

      {:ok, session, _token} =
        Hexpm.UserSessions.create_browser_session(user, audit: audit_data(user))

      expired = insert_authorization(user, session, days_ago(1))
      live = insert_authorization(user, session, hours_from_now(1))

      PurgeExpiredRecords.run()

      refute Repo.get(Hexpm.Accounts.SSO.Authorization, expired.id)
      assert Repo.get(Hexpm.Accounts.SSO.Authorization, live.id)
    end
  end

  defp insert_authorization(user, session, expires_at) do
    Repo.insert!(%Hexpm.Accounts.SSO.Authorization{
      code_hash: :crypto.strong_rand_bytes(32),
      user_id: user.id,
      user_session_id: session.id,
      organization_ids: [],
      expires_at: expires_at
    })
  end

  describe "purge organization SSO sessions" do
    test "deletes lapsed organization access sessions" do
      organization = insert(:organization)
      user = insert(:user)
      insert(:organization_user, organization: organization, user: user)
      connection = insert(:organization_sso_connection, organization: organization)

      identity =
        insert(:organization_sso_identity,
          organization: organization,
          connection: connection,
          user: user
        )

      active = insert_org_session(organization, user, identity, expires_at: hours_from_now(1))
      expired = insert_org_session(organization, user, identity, expires_at: days_ago(1))

      # Revoked but not yet expired. The purge collects on expiry alone, so this
      # one has to survive; with `days_ago(1)` it was deleted for the same
      # reason `expired` was and covered nothing.
      revoked =
        insert_org_session(organization, user, identity,
          expires_at: hours_from_now(1),
          revoked_at: DateTime.utc_now()
        )

      PurgeExpiredRecords.run()

      assert Repo.get(Hexpm.Accounts.SSO.OrgSession, active.id)
      refute Repo.get(Hexpm.Accounts.SSO.OrgSession, expired.id)
      assert Repo.get(Hexpm.Accounts.SSO.OrgSession, revoked.id)
    end
  end

  defp insert_org_session(organization, user, identity, attrs) do
    {:ok, user_session, _token} =
      Hexpm.UserSessions.create_browser_session(user, audit: audit_data(user))

    Repo.insert!(%Hexpm.Accounts.SSO.OrgSession{
      user_id: user.id,
      organization_id: organization.id,
      user_session_id: user_session.id,
      identity_id: identity.id,
      authenticated_at: DateTime.utc_now(),
      expires_at: Keyword.fetch!(attrs, :expires_at),
      revoked_at: Keyword.get(attrs, :revoked_at)
    })
  end

  defp hours_from_now(hours), do: DateTime.add(DateTime.utc_now(), hours * 3600, :second)

  describe "archive" do
    @credentials %{
      "authorization_codes" => ~w(code code_challenge),
      "device_codes" => ~w(device_code user_code verification_uri_complete),
      "oauth_tokens" => ~w(refresh_token_hash),
      "user_sessions" => ~w(session_token),
      "password_resets" => ~w(key),
      "account_deletion_requests" => ~w(key),
      "organization_sso_transactions" => ~w(state_hash nonce code_verifier link_token_hash),
      "organization_sso_sessions" => [],
      "organization_invitations" => ~w(token_hash),
      "keys" => ~w(secret_first secret_second)
    }

    test "writes every column but the credentials of each row it deletes" do
      expired = insert_expired_rows()

      PurgeExpiredRecords.run()

      assert map_size(expired) == map_size(@credentials)

      for {schema, id} <- expired do
        table = schema.__schema__(:source)
        refute Repo.get(schema, id)

        assert [archived] = archived_rows(table)
        assert archived["source_table"] == table
        assert archived["source_id"] == id
        assert {:ok, _archived_at, 0} = DateTime.from_iso8601(archived["archived_at"])

        columns = schema.__schema__(:fields) |> Enum.map(&Atom.to_string/1) |> Enum.sort()
        credentials = Map.fetch!(@credentials, table)
        assert Enum.sort(Map.keys(archived["row"])) == columns -- credentials
      end
    end

    test "writes nothing when there is nothing to purge" do
      PurgeExpiredRecords.run()

      assert Hexpm.Store.list(:audit_bucket, "") == []
    end

    test "round-trips arrays and embedded maps" do
      user = insert(:user)
      organization = insert(:organization)
      client = insert(:oauth_client)
      expires_at = truncated_seconds_ago(60)
      used_at = seconds_ago(3600)

      token =
        Repo.insert!(%Hexpm.OAuth.Token{
          jti: "expired-jti",
          token_type: "bearer",
          scopes: ["api", "repository:acme"],
          granted_scopes: ["api"],
          expires_at: expires_at,
          grant_type: "client_credentials",
          grant_reference: "key:1",
          user_id: user.id,
          organization_id: organization.id,
          client_id: client.client_id
        })

      session =
        Repo.insert!(%Hexpm.UserSession{
          type: "browser",
          name: "expired session",
          session_token: :crypto.strong_rand_bytes(32),
          expires_at: seconds_ago(60),
          user_id: user.id,
          last_use: %Hexpm.UserSession.Use{
            used_at: used_at,
            user_agent: "Mozilla/5.0",
            ip: "203.0.113.9"
          }
        })

      key =
        insert(:key,
          user: user,
          revoke_at: days_ago(91),
          permissions: [build(:key_permission, domain: "repository", resource: "acme")],
          last_use: %Hexpm.Accounts.Key.Use{
            used_at: used_at,
            user_agent: "Hex/2.1.1",
            ip: "203.0.113.10"
          }
        )

      PurgeExpiredRecords.run()

      assert [%{"row" => row}] = archived_rows("oauth_tokens")
      assert row["id"] == token.id
      assert row["jti"] == "expired-jti"
      assert row["scopes"] == ["api", "repository:acme"]
      assert row["granted_scopes"] == ["api"]
      assert row["user_id"] == user.id
      assert row["organization_id"] == organization.id
      assert row["client_id"] == client.client_id
      assert row["expires_at"] =~ ~r/^#{Calendar.strftime(expires_at, "%Y-%m-%dT%H:%M:%S")}/
      assert row["revoked_at"] == nil

      assert [%{"row" => row}] = archived_rows("user_sessions")
      assert row["id"] == session.id
      assert row["last_use"]["ip"] == "203.0.113.9"
      assert row["last_use"]["user_agent"] == "Mozilla/5.0"
      assert row["last_use"]["used_at"] =~ ~r/^#{Calendar.strftime(used_at, "%Y-%m-%dT%H:%M:%S")}/
      refute Map.has_key?(row, "session_token")

      assert [%{"row" => row}] = archived_rows("keys")
      assert row["id"] == key.id
      assert row["name"] == key.name
      assert [%{"domain" => "repository", "resource" => "acme"}] = row["permissions"]
      assert row["last_use"]["ip"] == "203.0.113.10"
      refute Map.has_key?(row, "secret_first")
      refute Map.has_key?(row, "secret_second")
    end

    test "leaves the rows in place when the upload fails" do
      app_env(:hexpm, :audit_bucket, {Hexpm.Store.Mock, "audit_bucket"})

      expect(Hexpm.Store.Mock, :put, fn "audit_bucket", _key, _body, _opts ->
        raise "upload failed"
      end)

      expired = insert_expired_rows()

      assert_raise RuntimeError, "upload failed", fn -> PurgeExpiredRecords.run() end

      for {schema, id} <- expired do
        assert Repo.get(schema, id)
      end
    end

    test "uploads one object per batch, named in sequence under one run" do
      user = insert(:user)
      client = insert(:oauth_client)

      for i <- 1..5 do
        Repo.insert!(%Hexpm.OAuth.Token{
          jti: "expired-jti-#{i}",
          token_type: "bearer",
          scopes: ["api"],
          expires_at: truncated_seconds_ago(60),
          grant_type: "authorization_code",
          user_id: user.id,
          client_id: client.client_id
        })
      end

      PurgeExpiredRecords.run(batch_size: 2)

      assert [first, second, third] = Enum.sort(Hexpm.Store.list(:audit_bucket, "oauth_tokens-"))

      assert first =~ ~r"^oauth_tokens-\d{8}T\d{6}Z-[0-9a-f]{8}-0001\.json\.gz$"

      run = String.replace_suffix(first, "-0001.json.gz", "")
      assert second == run <> "-0002.json.gz"
      assert third == run <> "-0003.json.gz"

      assert Enum.map([first, second, third], &length(archived_lines(&1))) == [2, 2, 1]
      assert Repo.aggregate(Hexpm.OAuth.Token, :count) == 0
    end
  end

  defp insert_expired_rows() do
    user = insert(:user)
    client = insert(:oauth_client)
    organization = insert(:organization)
    insert(:organization_user, organization: organization, user: user)
    connection = insert(:organization_sso_connection, organization: organization)

    identity =
      insert(:organization_sso_identity,
        organization: organization,
        connection: connection,
        user: user
      )

    code =
      Repo.insert!(%Hexpm.OAuth.AuthorizationCode{
        code: "expired-code",
        redirect_uri: "https://example.com/callback",
        scopes: ["api"],
        expires_at: truncated_seconds_ago(60),
        code_challenge: "challenge",
        code_challenge_method: "S256",
        user_id: user.id,
        client_id: client.client_id
      })

    device_code =
      Repo.insert!(%Hexpm.OAuth.DeviceCode{
        device_code: "expired-device",
        user_code: "EXPR1234",
        verification_uri: "https://hex.pm/device",
        verification_uri_complete: "https://hex.pm/device?user_code=EXPR1234",
        expires_at: seconds_ago(60),
        client_id: client.client_id
      })

    token =
      Repo.insert!(%Hexpm.OAuth.Token{
        jti: "expired-jti",
        refresh_token_hash: "refresh-hash",
        token_type: "bearer",
        scopes: ["api"],
        expires_at: truncated_seconds_ago(60),
        grant_type: "authorization_code",
        user_id: user.id,
        client_id: client.client_id
      })

    session =
      Repo.insert!(%Hexpm.UserSession{
        type: "browser",
        name: "expired session",
        session_token: :crypto.strong_rand_bytes(32),
        expires_at: seconds_ago(60),
        user_id: user.id
      })

    password_reset =
      Repo.insert!(%Hexpm.Accounts.PasswordReset{
        key: "old-key",
        primary_email: "old@example.com",
        user_id: user.id,
        inserted_at: days_ago(91)
      })

    deletion_request =
      Repo.insert!(%Hexpm.Accounts.AccountDeletionRequest{
        key: "old-key",
        primary_email: "old@example.com",
        user_id: user.id,
        inserted_at: days_ago(91)
      })

    transaction =
      Repo.insert!(%Hexpm.Accounts.SSO.Transaction{
        connection_id: connection.id,
        state_hash: :crypto.hash(:sha256, "expired-state"),
        nonce: "nonce",
        code_verifier: "verifier",
        link_token_hash: :crypto.hash(:sha256, "link"),
        kind: "login",
        secret_slot: "active",
        connection_version: connection.version,
        secret_version: connection.version,
        redirect_uri: "https://hex.pm/sso/callback",
        issuer: connection.issuer,
        subject: "00u123",
        provider_email: "member@example.com",
        expires_at: days_ago(1)
      })

    org_session = insert_org_session(organization, user, identity, expires_at: days_ago(1))

    invitation =
      insert(:organization_invitation,
        organization: organization,
        invited_by_user: user,
        expires_at: days_ago(1)
      )

    key = insert(:key, user: user, revoke_at: days_ago(91))

    %{
      Hexpm.OAuth.AuthorizationCode => code.id,
      Hexpm.OAuth.DeviceCode => device_code.id,
      Hexpm.OAuth.Token => token.id,
      Hexpm.UserSession => session.id,
      Hexpm.Accounts.PasswordReset => password_reset.id,
      Hexpm.Accounts.AccountDeletionRequest => deletion_request.id,
      Hexpm.Accounts.SSO.Transaction => transaction.id,
      Hexpm.Accounts.SSO.OrgSession => org_session.id,
      Hexpm.Accounts.OrganizationInvitation => invitation.id,
      Hexpm.Accounts.Key => key.id
    }
  end

  defp archived_rows(table) do
    :audit_bucket
    |> Hexpm.Store.list("#{table}-")
    |> Enum.sort()
    |> Enum.flat_map(&archived_lines/1)
  end

  defp archived_lines(key) do
    :audit_bucket
    |> Hexpm.Store.get(key)
    |> :zlib.gunzip()
    |> String.split("\n", trim: true)
    |> Enum.map(&JSON.decode!/1)
  end
end
