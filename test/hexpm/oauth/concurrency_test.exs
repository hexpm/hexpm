defmodule Hexpm.OAuth.ConcurrencyTest do
  use Hexpm.DataCase
  import Hexpm.ConcurrencyCase

  alias Ecto.Adapters.SQL.Sandbox
  alias Hexpm.OAuth.{AuthorizationCode, AuthorizationCodes, Client, Token, Tokens}
  alias Hexpm.{UserSession, UserSessions}

  @code_challenge "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
  @redirect_uri "https://example.com/callback"

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
