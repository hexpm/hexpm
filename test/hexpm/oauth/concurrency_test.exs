defmodule Hexpm.OAuth.ConcurrencyTest do
  use Hexpm.DataCase
  import Hexpm.ConcurrencyCase

  alias Ecto.Adapters.SQL.Sandbox
  alias Hexpm.Accounts.{SSO, TFASessions}
  alias Hexpm.OAuth.{AuthorizationCode, AuthorizationCodes, Client, Token, Tokens}
  alias Hexpm.{UserSession, UserSessions}

  @code_challenge "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
  @redirect_uri "https://example.com/callback"

  setup do
    app_env(:hexpm, :organization_tfa, mode: :enabled, beta_organizations: [])
    :ok
  end

  test "two redemptions of one authorization code leave one session and one token" do
    committed(fn context ->
      auth_code = authorization_code(context)

      results = race(2, fn -> redeem(context, auth_code) end)

      assert Enum.count(results, &match?({:ok, %Token{}}, &1)) == 1
      assert Enum.count(results, &match?({:error, :already_used}, &1)) == 1
      assert committed_count(context, UserSession) == 1
      assert token_count(context) == 1
    end)
  end

  test "a redemption waiting on the transaction that consumed the code is refused" do
    committed(fn context ->
      auth_code = authorization_code(context)
      parent = self()

      consumer =
        unboxed_task(fn ->
          Repo.transaction(fn ->
            {:ok, _consumed} = AuthorizationCodes.consume(auth_code)
            send(parent, :consumed)

            receive do
              :release -> :ok
            end
          end)
        end)

      assert_receive :consumed, 15_000

      redemption = unboxed_task(fn -> redeem(context, auth_code) end)

      refute Task.yield(redemption, 500)

      send(consumer.pid, :release)
      assert {:ok, :ok} = Task.await(consumer, 15_000)
      assert {:error, :already_used} = Task.await(redemption, 15_000)
      assert token_count(context) == 0
    end)
  end

  test "a failed redemption leaves the code redeemable" do
    committed(fn context ->
      auth_code = authorization_code(context)

      assert {:error, %Ecto.Changeset{}} =
               redeem(context, %{auth_code | scopes: ["not-a-scope"]})

      assert Repo.get!(AuthorizationCode, auth_code.id).used_at == nil
      assert {:ok, %Token{}} = redeem(context, auth_code)
    end)
  end

  test "two refreshes of one token issue a single replacement" do
    committed(fn context ->
      token = session_token(context)

      results = race(2, fn -> refresh(context, token) end)

      assert Enum.count(results, &match?({:ok, %Token{}}, &1)) == 1
      assert Enum.count(results, &match?({:error, :token_revoked}, &1)) == 1
      assert live_token_count(context) == 1
    end)
  end

  test "a refresh waiting on a session revocation is refused" do
    committed(fn context ->
      token = session_token(context)
      session = Repo.get!(UserSession, token.user_session_id)
      parent = self()

      revocation =
        unboxed_task(fn ->
          Repo.transaction(fn ->
            {:ok, _revoked} = UserSessions.revoke(session)
            send(parent, :revoked)

            receive do
              :release -> :ok
            end
          end)
        end)

      assert_receive :revoked, 15_000

      refresh = unboxed_task(fn -> refresh(context, token) end)

      refute Task.yield(refresh, 500)

      send(revocation.pid, :release)
      assert {:ok, :ok} = Task.await(revocation, 15_000)
      assert {:error, :token_revoked} = Task.await(refresh, 15_000)
      assert live_token_count(context) == 0
    end)
  end

  test "device approval and OTP verification use compatible lock order at the session limit" do
    committed(fn context ->
      alias Hexpm.Accounts.TFASessions
      alias Hexpm.OAuth.DeviceCodes

      user = insert(:user_with_tfa)

      old =
        insert(:oauth_session,
          user: user,
          client_id: context.client.client_id,
          inserted_at: DateTime.add(DateTime.utc_now(), -3600)
        )

      browser = insert(:session, user: user, expires_at: DateTime.add(DateTime.utc_now(), 86400))
      {:ok, :ok} = TFASessions.record_verified!(user, browser.id)
      for _ <- 1..3, do: insert(:oauth_session, user: user, client_id: context.client.client_id)

      {:ok, device} =
        DeviceCodes.initiate_device_authorization(
          Phoenix.ConnTest.build_conn(),
          context.client.client_id,
          ["api:read"]
        )

      parent = self()

      verifier =
        unboxed_task(fn ->
          Repo.transaction(fn ->
            TFASessions.lock_user!(user)
            send(parent, :user_locked)

            receive do
              :continue -> :ok
            after
              5000 -> raise "verification was not released"
            end

            TFASessions.record_verified!(user, old.id)
          end)
        end)

      assert_receive :user_locked, 5000

      approval =
        unboxed_task(fn ->
          %{rows: [[pid]]} =
            Ecto.Adapters.SQL.query!(Hexpm.RepoBase, "SELECT pg_backend_pid()", [])

          send(parent, {:approval_pid, pid})

          DeviceCodes.authorize_device(device.user_code, user, ["api:read"],
            browser_session_id: browser.id,
            audit: audit_data(user)
          )
        end)

      assert_receive {:approval_pid, pid}, 5000
      wait_for_lock(pid, 100)
      send(verifier.pid, :continue)
      assert {:ok, {:ok, :ok}} = Task.await(verifier, 10000)
      assert {:ok, _} = Task.await(approval, 10000)

      session =
        Repo.one!(
          from s in UserSession,
            where: s.user_id == ^user.id and s.type == "oauth" and is_nil(s.revoked_at),
            order_by: [desc: s.id],
            limit: 1
        )

      assert TFASessions.proof(user, session.id).tfa_source_session_id == browser.id
      assert Repo.get!(UserSession, old.id).revoked_at
    end)
  end

  test "completed organization authorization refuses a waiting cancellation" do
    committed(fn context ->
      context = organization_authorization(context)
      parent = self()

      completion =
        unboxed_task(fn ->
          Repo.transaction(fn ->
            {:ok, :ok} =
              SSO.complete_authorization(context.authorization, context.user, context.browser.id)

            send(parent, :completed)

            receive do
              :release -> :ok
            after
              5000 -> raise "completion was not released"
            end
          end)
        end)

      assert_receive :completed, 5000

      cancellation =
        unboxed_task(fn ->
          %{rows: [[pid]]} =
            Ecto.Adapters.SQL.query!(Hexpm.RepoBase, "SELECT pg_backend_pid()", [])

          send(parent, {:cancellation_pid, pid})
          SSO.consume_authorization!(context.authorization)
        end)

      assert_receive {:cancellation_pid, pid}, 5000
      wait_for_lock(pid, 100)
      send(completion.pid, :release)
      assert {:ok, :ok} = Task.await(completion, 10000)
      assert {:error, :invalid_authorization} = Task.await(cancellation, 10000)
      assert TFASessions.proof(context.user, context.target.id)
      refute SSO.get_authorization(context.authorization.raw_code, context.user)
      assert Repo.get!(UserSession, context.target.id).expires_at == context.target.expires_at
    end)
  end

  test "cancelled organization authorization refuses waiting completion without copying proof" do
    committed(fn context ->
      context = organization_authorization(context)
      parent = self()

      cancellation =
        unboxed_task(fn ->
          Repo.transaction(fn ->
            :ok = SSO.consume_authorization!(context.authorization)
            send(parent, :cancelled)

            receive do
              :release -> :ok
            after
              5000 -> raise "cancellation was not released"
            end
          end)
        end)

      assert_receive :cancelled, 5000

      completion =
        unboxed_task(fn ->
          %{rows: [[pid]]} =
            Ecto.Adapters.SQL.query!(Hexpm.RepoBase, "SELECT pg_backend_pid()", [])

          send(parent, {:completion_pid, pid})
          SSO.complete_authorization(context.authorization, context.user, context.browser.id)
        end)

      assert_receive {:completion_pid, pid}, 5000
      wait_for_lock(pid, 100)
      send(cancellation.pid, :release)
      assert {:ok, :ok} = Task.await(cancellation, 10000)
      assert {:error, :invalid_authorization} = Task.await(completion, 10000)
      refute TFASessions.proof(context.user, context.target.id)
      refute SSO.get_authorization(context.authorization.raw_code, context.user)
      assert Repo.get!(UserSession, context.target.id).expires_at == context.target.expires_at
    end)
  end

  defp organization_authorization(context) do
    user = insert(:user_with_tfa)
    organization = insert(:organization, tfa_required_at: DateTime.add(DateTime.utc_now(), -1))
    insert(:organization_user, user: user, organization: organization, role: "admin")
    browser = insert(:session, user: user, expires_at: DateTime.add(DateTime.utc_now(), 86400))
    {:ok, :ok} = TFASessions.record_verified!(user, browser.id)
    target = insert(:oauth_session, user: user, client_id: context.client.client_id)

    {:ok, authorization} =
      SSO.request_authorization(user, target.id, [organization.name],
        redirect_uri: @redirect_uri,
        state: "authorization-race-state"
      )

    %{user: user, browser: browser, target: target, authorization: authorization}
  end

  defp wait_for_lock(_, 0), do: flunk("competing transaction did not wait for a lock")

  defp wait_for_lock(pid, attempts) do
    %{rows: rows} =
      Ecto.Adapters.SQL.query!(
        Hexpm.RepoBase,
        "SELECT wait_event_type FROM pg_stat_activity WHERE pid=$1",
        [pid]
      )

    if rows != [["Lock"]] do
      Process.sleep(20)
      wait_for_lock(pid, attempts - 1)
    end
  end

  defp redeem(context, auth_code) do
    Tokens.create_session_and_token_for_user(
      context.user,
      context.client.client_id,
      auth_code.scopes,
      "authorization_code",
      auth_code.code,
      with_refresh_token: true,
      audit: audit_data(context.user),
      authorization_code: auth_code
    )
  end

  defp refresh(context, token) do
    Tokens.revoke_and_create_token(
      token,
      context.client.client_id,
      token.granted_scopes,
      "refresh_token",
      token.refresh_token,
      with_refresh_token: true,
      user_session_id: token.user_session_id,
      usage_info: %{used_at: DateTime.utc_now(), user_agent: "test", ip: "127.0.0.1"}
    )
  end

  defp authorization_code(context) do
    {:ok, auth_code} =
      AuthorizationCodes.create_and_insert_for_user(
        context.user,
        context.client.client_id,
        @redirect_uri,
        ["api"],
        code_challenge: @code_challenge
      )

    auth_code
  end

  defp session_token(context) do
    {:ok, token} =
      Tokens.create_session_and_token_for_user(
        context.user,
        context.client.client_id,
        ["api"],
        "authorization_code",
        "code",
        with_refresh_token: true,
        audit: audit_data(context.user)
      )

    Repo.preload(token, :user)
  end

  defp token_count(context) do
    Repo.aggregate(from(t in Token, where: t.client_id == ^context.client.client_id), :count)
  end

  defp live_token_count(context) do
    from(t in Token, where: t.client_id == ^context.client.client_id, where: is_nil(t.revoked_at))
    |> Repo.aggregate(:count)
  end

  # The rows these tests commit in the OAuth tables outlive the transaction that
  # made them, and `Hexpm.ConcurrencyCase` only knows how to clean up its own
  # list. Registered inside the context so it runs before that cleanup, which
  # deletes the users and sessions these rows point at.
  defp committed(fun) do
    committed(&build_context/0, fn context ->
      on_exit(fn ->
        Sandbox.unboxed_run(Hexpm.RepoBase, fn ->
          Hexpm.RepoBase.delete_all(
            from(t in Token, where: t.client_id == ^context.client.client_id)
          )

          Hexpm.RepoBase.delete_all(
            from(c in AuthorizationCode, where: c.client_id == ^context.client.client_id)
          )

          Hexpm.RepoBase.delete_all(
            from(d in Hexpm.OAuth.DeviceCode, where: d.client_id == ^context.client.client_id)
          )

          Hexpm.RepoBase.delete_all(
            from(c in Client, where: c.client_id == ^context.client.client_id)
          )
        end)
      end)

      fun.(context)
    end)
  end

  defp build_context do
    %{user: insert(:user), client: insert(:oauth_client)}
  end
end
