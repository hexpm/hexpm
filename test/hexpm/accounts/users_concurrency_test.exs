defmodule Hexpm.Accounts.UsersConcurrencyTest do
  use Hexpm.DataCase
  import Hexpm.ConcurrencyCase

  alias Hexpm.Accounts.{Users, User}
  alias Hexpm.Accounts.SSO.OrgSession
  alias Hexpm.OAuth.{Client, Token, Tokens}
  alias Hexpm.{UserSession, UserSessions}

  # Each of these fails if Users.lock!/1 stops being taken before the one-time
  # secret is checked: both racers read it unused and both succeed.

  test "a password reset key resets the password once" do
    committed(fn -> %{user: insert(:user)} end, fn context ->
      :ok = Users.password_reset_init(context.user.username, audit: audit_data(context.user))
      reset_key = password_reset_key()

      results =
        race(["first_password_123", "second_password_123"], fn password ->
          Users.password_reset_finish(
            context.user.username,
            reset_key,
            %{"password" => password, "password_confirmation" => password},
            false,
            audit: audit_data(context.user)
          )
        end)

      assert Enum.sort(results) == [:error, :ok]
    end)
  end

  test "a recovery code is accepted once" do
    committed(fn -> %{user: insert(:user_with_tfa)} end, fn context ->
      [code | _] = context.user.tfa.recovery_codes

      results = race(2, fn -> Users.tfa_recover(context.user, code.code) end)

      assert Enum.count(results, &match?({:ok, %User{}}, &1)) == 1
      assert Enum.count(results, &(&1 == {:error, :invalid_code})) == 1
    end)
  end

  # Revoking a browser session locks it and then the organization access written
  # against it. Anything else that revokes sessions has to take the rows in the
  # same order, or the two deadlock and Postgres aborts one of them.
  test "a password change waits for a logout of another session instead of deadlocking" do
    committed(&sessions_context/0, fn context ->
      change = fn ->
        Users.update_password(
          context.user,
          context.current_session,
          %{
            "password_current" => "password",
            "password" => "new_password_123",
            "password_confirmation" => "new_password_123"
          },
          audit: audit_data(context.user)
        )
      end

      assert {{:ok, _count}, {:ok, %User{}}} = during_logout(context.other_session, change)
    end)
  end

  test "a password reset waits for a logout of another session instead of deadlocking" do
    committed(&sessions_context/0, fn context ->
      :ok = Users.password_reset_init(context.user.username, audit: audit_data(context.user))
      reset_key = password_reset_key()

      reset = fn ->
        Users.password_reset_finish(
          context.user.username,
          reset_key,
          %{"password" => "new_password_123", "password_confirmation" => "new_password_123"},
          false,
          audit: audit_data(context.user)
        )
      end

      assert {{:ok, _count}, :ok} = during_logout(context.other_session, reset)
    end)
  end

  test "a login evicting a session waits for a logout of it instead of deadlocking" do
    committed(&eviction_context/0, fn context ->
      login = fn ->
        UserSessions.create_browser_session(context.user, audit: audit_data(context.user))
      end

      assert {{:ok, _count}, {:ok, _session, _token}} =
               during_logout(context.oldest_session, login)

      assert Hexpm.RepoBase.get!(UserSession, context.oldest_session.id).revoked_at
    end)
  end

  # A password change locks the account and then its tokens, so deleting the
  # account has to take them in the same order.
  test "an account deletion waits for a password change instead of deadlocking" do
    committed(&token_context/0, fn context ->
      user = context.user

      password_change_steps = {
        fn -> from(u in User, where: u.id == ^user.id) end,
        fn -> from(token in Token, where: token.user_id == ^user.id) end
      }

      deletion = fn -> Users.delete(user, audit: audit_data(user)) end

      assert {{:ok, _count}, :ok} = while_holding(password_change_steps, deletion)
      refute Hexpm.RepoBase.get(User, user.id)
    end)
  end

  # Runs `fun` while a logout of `session` holds the session row and has yet to
  # revoke its organization access, then lets the logout finish.
  defp during_logout(session, fun) do
    logout_steps = {
      fn -> from(user_session in UserSession, where: user_session.id == ^session.id) end,
      fn -> from(org_session in OrgSession, where: org_session.user_session_id == ^session.id) end
    }

    while_holding(logout_steps, fun)
  end

  # Runs `fun` while another transaction has updated the rows of the first query
  # and has yet to update the rows of the second, then lets it finish.
  defp while_holding({first, second}, fun) do
    parent = self()

    holder =
      unboxed_task(fn ->
        Hexpm.RepoBase.transaction(fn ->
          Hexpm.RepoBase.update_all(first.(), set: [updated_at: DateTime.utc_now()])
          send(parent, :locked)
          assert_receive :continue, 15_000
          {count, _} = Hexpm.RepoBase.update_all(second.(), set: [updated_at: DateTime.utc_now()])
          count
        end)
      end)

    assert_receive :locked, 15_000
    task = unboxed_task(fun)

    assert await_lock_wait() == :waiting
    send(holder.pid, :continue)

    {Task.await(holder, 15_000), Task.await(task, 15_000)}
  end

  defp token_context do
    user = insert(:user)
    client = insert(:oauth_client)
    session = insert(:oauth_session, user: user, client_id: client.client_id)

    on_exit(fn ->
      Ecto.Adapters.SQL.Sandbox.unboxed_run(Hexpm.RepoBase, fn ->
        Hexpm.RepoBase.delete_all(from(c in Client, where: c.client_id == ^client.client_id))
      end)
    end)

    {:ok, _token} =
      Tokens.create_and_insert_for_user(
        user,
        client.client_id,
        ["api:read"],
        "authorization_code",
        "test",
        user_session_id: session.id
      )

    %{user: user}
  end

  # A user at the session limit whose least recently used session carries
  # organization access, so the next login evicts it.
  defp eviction_context do
    %{user: user, current_session: oldest_session} = sessions_context()

    Hexpm.RepoBase.update_all(
      from(session in UserSession, where: session.id == ^oldest_session.id),
      set: [inserted_at: DateTime.add(DateTime.utc_now(), -3600, :second)]
    )

    for _ <- 3..UserSessions.max_user_sessions() do
      {:ok, _session, _token} = UserSessions.create_browser_session(user, audit: audit_data(user))
    end

    %{user: user, oldest_session: oldest_session}
  end

  defp sessions_context do
    user = insert(:user)
    organization = insert(:organization)
    connection = insert(:organization_sso_connection, organization: organization)

    identity =
      insert(:organization_sso_identity,
        connection: connection,
        organization: organization,
        user: user
      )

    [current_session, other_session] =
      for _ <- 1..2 do
        {:ok, session, _token} =
          UserSessions.create_browser_session(user, audit: audit_data(user))

        Hexpm.RepoBase.insert!(%OrgSession{
          user_id: user.id,
          organization_id: organization.id,
          user_session_id: session.id,
          identity_id: identity.id,
          authenticated_at: DateTime.utc_now(),
          expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
        })

        session
      end

    %{user: user, current_session: current_session, other_session: other_session}
  end
end
