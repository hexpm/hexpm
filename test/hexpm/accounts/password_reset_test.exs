defmodule Hexpm.Accounts.PasswordResetTest do
  use Hexpm.DataCase, async: true

  alias Hexpm.Accounts.{PasswordReset, Users}

  test "stores a hash of the mailed key, never the key" do
    user = insert(:user)
    :ok = Users.password_reset_init(user.username, audit: audit_data(user))
    key = password_reset_key()

    [reset] = Repo.preload(user, :password_resets).password_resets
    assert reset.key_hash == :crypto.hash(:sha256, key)
    assert reset.key == nil
  end

  describe "can_reset?/3" do
    test "returns true for valid reset within 24 hours" do
      reset = %PasswordReset{
        key_hash: :crypto.hash(:sha256, "valid_key"),
        primary_email: "test@example.com",
        inserted_at: NaiveDateTime.utc_now()
      }

      assert PasswordReset.can_reset?(reset, "test@example.com", "valid_key")
    end

    test "returns false when key does not match" do
      reset = %PasswordReset{
        key_hash: :crypto.hash(:sha256, "valid_key"),
        primary_email: "test@example.com",
        inserted_at: NaiveDateTime.utc_now()
      }

      refute PasswordReset.can_reset?(reset, "test@example.com", "wrong_key")
    end

    test "returns false when email does not match" do
      reset = %PasswordReset{
        key_hash: :crypto.hash(:sha256, "valid_key"),
        primary_email: "test@example.com",
        inserted_at: NaiveDateTime.utc_now()
      }

      refute PasswordReset.can_reset?(reset, "other@example.com", "valid_key")
    end

    test "returns false when reset is older than 24 hours" do
      # Create a reset that is 25 hours old
      expired_time = NaiveDateTime.add(NaiveDateTime.utc_now(), -25 * 60 * 60, :second)

      reset = %PasswordReset{
        key_hash: :crypto.hash(:sha256, "valid_key"),
        primary_email: "test@example.com",
        inserted_at: expired_time
      }

      refute PasswordReset.can_reset?(reset, "test@example.com", "valid_key")
    end

    test "returns false when the given key is nil" do
      reset = %PasswordReset{
        key_hash: :crypto.hash(:sha256, "valid_key"),
        primary_email: "test@example.com",
        inserted_at: NaiveDateTime.utc_now()
      }

      refute PasswordReset.can_reset?(reset, "test@example.com", nil)
    end
  end
end
