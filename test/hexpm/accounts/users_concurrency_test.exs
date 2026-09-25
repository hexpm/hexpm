defmodule Hexpm.Accounts.UsersConcurrencyTest do
  use Hexpm.DataCase
  import Hexpm.ConcurrencyCase

  alias Hexpm.Accounts.{Users, User}

  # Each of these fails if Users.lock!/1 stops being taken before the one-time
  # secret is checked: both racers read it unused and both succeed.

  test "a password reset key resets the password once" do
    committed(fn -> %{user: insert(:user)} end, fn context ->
      :ok = Users.password_reset_init(context.user.username, audit: audit_data(context.user))
      [reset] = Users.get_by_id(context.user.id, [:password_resets]).password_resets

      results =
        race(["first_password_123", "second_password_123"], fn password ->
          Users.password_reset_finish(
            context.user.username,
            reset.key,
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
end
