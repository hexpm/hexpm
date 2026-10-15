defmodule Hexpm.Accounts.UsersConcurrencyTest do
  use Hexpm.DataCase
  import Hexpm.ConcurrencyCase

  alias Hexpm.Accounts.{Users, User}
  alias Hexpm.Accounts.SSO.OrgSession
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
  # against it. A password change has to take the rows in the same order, or the
  # two deadlock and Postgres aborts one of them.
  test "a password change waits for a logout of another session instead of deadlocking" do
    committed(&sessions_context/0, fn context ->
      parent = self()

      logout =
        unboxed_task(fn ->
          Hexpm.RepoBase.transaction(fn ->
            Hexpm.RepoBase.one!(
              from(session in UserSession,
                where: session.id == ^context.other_session.id,
                lock: "FOR UPDATE"
              )
            )

            send(parent, :locked)
            assert_receive :continue, 15_000

            Hexpm.RepoBase.update_all(
              from(session in OrgSession,
                where: session.user_session_id == ^context.other_session.id
              ),
              set: [revoked_at: DateTime.utc_now()]
            )
          end)
        end)

      assert_receive :locked, 15_000

      change =
        unboxed_task(fn ->
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
        end)

      assert await_lock_wait() == :waiting
      send(logout.pid, :continue)

      assert {:ok, _count} = Task.await(logout, 15_000)
      assert {:ok, %User{}} = Task.await(change, 15_000)
    end)
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
