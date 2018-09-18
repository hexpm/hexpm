defmodule Hexpm.Accounts.AuthTest do
  use Hexpm.DataCase, async: true

  alias Hexpm.Accounts.{Auth, Key}

  setup do
    user = insert(:user, password: Auth.gen_password("password"))
    %{user: user, password: "password"}
  end

  describe "password_auth/2" do
    test "authorizes correct password", %{user: user, password: password} do
      assert {:ok, %{user: auth_user, email: email, source: :password}} =
               Auth.password_auth(user.username, password)

      assert auth_user.id == user.id
      assert email.id == hd(user.emails).id
    end

    test "does not authorize wrong password", %{user: user, password: password} do
      assert Auth.password_auth("some_invalid_username", password) == :error
      assert Auth.password_auth(user.username, "some_wrong_password") == :error
    end
  end

  describe "key_auth/2" do
    test "authorizes correct key", %{user: user} do
      key = insert(:key, user: user)

      assert {:ok, %{user: auth_user, key: auth_key, email: email, source: :key}} =
               Auth.key_auth(key.user_secret, %{})

      assert auth_key.id == key.id
      assert auth_user.id == user.id
      assert email.id == hd(user.emails).id
    end

    test "stores key usage information when used", %{user: user} do
      key = insert(:key, user: user)
      timestamp = DateTime.utc_now()

      usage_info = %{
        used_at: timestamp,
        user_agent: ["Chrome"],
        ip: {127, 0, 0, 1}
      }

      {:ok, _} = Auth.key_auth(key.user_secret, usage_info)

      key = Repo.get(Key, key.id)
      assert key.last_use.used_at == timestamp
      assert key.last_use.user_agent == "Chrome"
      assert key.last_use.ip == "127.0.0.1"
    end

    test "does not authorize wrong key" do
      assert Auth.key_auth("0123456789abcdef", %{}) == :error
    end

    test "does not authorize revoked key", %{user: user} do
      key = insert(:key, user: user, revoked_at: ~N"2017-01-01 00:00:00")
      assert Auth.key_auth(key.user_secret, %{}) == :revoked
    end
  end
end
