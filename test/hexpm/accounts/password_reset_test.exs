defmodule Hexpm.Accounts.PasswordResetTest do
  use Hexpm.DataCase, async: true

  alias Hexpm.Accounts.PasswordReset

  describe "can_reset?/3" do
    test "returns true for valid reset within 24 hours" do
      reset = %PasswordReset{
        key: "valid_key",
        primary_email: "test@example.com",
        inserted_at: NaiveDateTime.utc_now()
      }

      assert PasswordReset.can_reset?(reset, "test@example.com", "valid_key")
    end

    test "returns false when key does not match" do
      reset = %PasswordReset{
        key: "valid_key",
        primary_email: "test@example.com",
        inserted_at: NaiveDateTime.utc_now()
      }

      refute PasswordReset.can_reset?(reset, "test@example.com", "wrong_key")
    end

    test "returns false when email does not match" do
      reset = %PasswordReset{
        key: "valid_key",
        primary_email: "test@example.com",
        inserted_at: NaiveDateTime.utc_now()
      }

      refute PasswordReset.can_reset?(reset, "other@example.com", "valid_key")
    end

    test "returns false when reset is older than 24 hours" do
      # Create a reset that is 25 hours old
      expired_time = NaiveDateTime.add(NaiveDateTime.utc_now(), -25 * 60 * 60, :second)

      reset = %PasswordReset{
        key: "valid_key",
        primary_email: "test@example.com",
        inserted_at: expired_time
      }

      refute PasswordReset.can_reset?(reset, "test@example.com", "valid_key")
    end

    test "returns false when key is nil" do
      reset = %PasswordReset{
        key: nil,
        primary_email: "test@example.com",
        inserted_at: NaiveDateTime.utc_now()
      }

      refute PasswordReset.can_reset?(reset, "test@example.com", "any_key")
    end
  end
end
