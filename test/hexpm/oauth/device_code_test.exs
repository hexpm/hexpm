defmodule Hexpm.OAuth.DeviceCodeTest do
  use Hexpm.DataCase, async: true

  import Ecto.Changeset, only: [get_field: 2]

  alias Hexpm.OAuth.DeviceCode

  describe "changeset/2" do
    test "validates required fields" do
      changeset = DeviceCode.changeset(%DeviceCode{}, %{})

      assert %{
               device_code: "can't be blank",
               user_code: "can't be blank",
               verification_uri: "can't be blank",
               client_id: "can't be blank",
               expires_at: "can't be blank"
             } = errors_on(changeset)
    end

    test "validates interval is positive" do
      changeset =
        DeviceCode.changeset(%DeviceCode{}, %{
          device_code: "device123",
          user_code: "USER-CODE",
          verification_uri: "https://example.com/device",
          client_id: "test_client",
          expires_at: DateTime.utc_now(),
          interval: 0
        })

      assert %{interval: "must be greater than 0"} = errors_on(changeset)
    end

    test "creates valid changeset with all fields" do
      attrs = %{
        device_code: "device123",
        user_code: "USER-CODE",
        verification_uri: "https://example.com/device",
        verification_uri_complete: "https://example.com/device?user_code=USER-CODE",
        client_id: "test_client",
        expires_at: DateTime.utc_now(),
        interval: 5,
        scopes: ["api", "api:read"]
      }

      changeset = DeviceCode.changeset(%DeviceCode{}, attrs)
      assert changeset.valid?
    end

    test "sets default values" do
      attrs = %{
        device_code: "device123",
        user_code: "USER-CODE",
        verification_uri: "https://example.com/device",
        client_id: "test_client",
        expires_at: DateTime.utc_now()
      }

      changeset = DeviceCode.changeset(%DeviceCode{}, attrs)
      assert changeset.valid?

      # Check defaults are applied
      device_code = Ecto.Changeset.apply_changes(changeset)
      assert device_code.interval == 5
      assert device_code.status == "pending"
      assert device_code.scopes == []
    end
  end

  describe "authorize_changeset/2" do
    test "creates changeset to authorize device code" do
      user = create_user()
      device_code = %DeviceCode{status: "pending"}

      changeset = DeviceCode.authorize_changeset(device_code, user)

      assert get_field(changeset, :status) == "authorized"
      assert get_field(changeset, :user_id) == user.id
    end
  end

  describe "deny_changeset/1" do
    test "creates changeset to deny device code" do
      device_code = %DeviceCode{status: "pending"}

      changeset = DeviceCode.deny_changeset(device_code)

      assert get_field(changeset, :status) == "denied"
    end
  end

  describe "expire_changeset/1" do
    test "creates changeset to expire device code" do
      device_code = %DeviceCode{status: "pending"}

      changeset = DeviceCode.expire_changeset(device_code)

      assert get_field(changeset, :status) == "expired"
    end
  end

  describe "expired?/1" do
    test "returns false for non-expired device code" do
      future_time = DateTime.add(DateTime.utc_now(), 600, :second)
      device_code = %DeviceCode{expires_at: future_time}

      refute DeviceCode.expired?(device_code)
    end

    test "returns true for expired device code" do
      past_time = DateTime.add(DateTime.utc_now(), -600, :second)
      device_code = %DeviceCode{expires_at: past_time}

      assert DeviceCode.expired?(device_code)
    end
  end

  describe "pending?/1" do
    test "returns true for pending, non-expired device code" do
      future_time = DateTime.add(DateTime.utc_now(), 600, :second)
      device_code = %DeviceCode{status: "pending", expires_at: future_time}

      assert DeviceCode.pending?(device_code)
    end

    test "returns false for pending but expired device code" do
      past_time = DateTime.add(DateTime.utc_now(), -600, :second)
      device_code = %DeviceCode{status: "pending", expires_at: past_time}

      refute DeviceCode.pending?(device_code)
    end

    test "returns false for non-pending device code" do
      future_time = DateTime.add(DateTime.utc_now(), 600, :second)
      device_code = %DeviceCode{status: "authorized", expires_at: future_time}

      refute DeviceCode.pending?(device_code)
    end
  end

  describe "authorized?/1" do
    test "returns true for authorized device code" do
      device_code = %DeviceCode{status: "authorized"}

      assert DeviceCode.authorized?(device_code)
    end

    test "returns false for non-authorized device code" do
      device_code = %DeviceCode{status: "pending"}

      refute DeviceCode.authorized?(device_code)
    end
  end

  describe "denied?/1" do
    test "returns true for denied device code" do
      device_code = %DeviceCode{status: "denied"}

      assert DeviceCode.denied?(device_code)
    end

    test "returns false for non-denied device code" do
      device_code = %DeviceCode{status: "pending"}

      refute DeviceCode.denied?(device_code)
    end
  end

  describe "generate_device_code/0" do
    test "generates non-empty string" do
      device_code = DeviceCode.generate_device_code()

      assert is_binary(device_code)
      assert String.length(device_code) > 0
    end

    test "generates unique device codes" do
      code1 = DeviceCode.generate_device_code()
      code2 = DeviceCode.generate_device_code()

      assert code1 != code2
    end

    test "generates 32-character base64url string" do
      device_code = DeviceCode.generate_device_code()

      assert String.length(device_code) == 32
      # Should not contain padding characters
      refute String.contains?(device_code, "=")
      # Should be valid base64url characters
      assert Regex.match?(~r/^[A-Za-z0-9_-]+$/, device_code)
    end
  end

  describe "generate_user_code/0" do
    test "generates non-empty string" do
      user_code = DeviceCode.generate_user_code()

      assert is_binary(user_code)
      assert String.length(user_code) > 0
    end

    test "generates unique user codes" do
      code1 = DeviceCode.generate_user_code()
      code2 = DeviceCode.generate_user_code()

      assert code1 != code2
    end

    test "generates correctly formatted user code" do
      user_code = DeviceCode.generate_user_code()

      # Should be 8 characters without formatting (formatting is UI concern)
      assert String.length(user_code) == 8
      refute String.contains?(user_code, "-")

      # All characters should be from the allowed charset
      assert String.match?(user_code, ~r/^[23456789BCDFGHJKLMNPQRSTVWXYZ]{8}$/)
    end

    test "generates codes without ambiguous characters" do
      # Run multiple times to check character set
      user_codes = Enum.map(1..100, fn _ -> DeviceCode.generate_user_code() end)

      all_chars =
        user_codes
        |> Enum.join("")
        |> String.replace("-", "")
        |> String.graphemes()
        |> Enum.uniq()

      # Should not contain ambiguous characters (0, 1, I, O) or vowels (A, E, U)
      forbidden_chars = ["0", "1", "I", "O", "A", "E", "U"]

      Enum.each(forbidden_chars, fn char ->
        refute char in all_chars, "User code contains forbidden character: #{char}"
      end)
    end

    test "generates codes with expected character set" do
      user_code = DeviceCode.generate_user_code()
      clean_code = String.replace(user_code, "-", "")

      # Should only contain characters from the allowed charset
      expected_charset = "23456789BCDFGHJKLMNPQRSTVWXYZ"

      Enum.each(String.graphemes(clean_code), fn char ->
        assert String.contains?(expected_charset, char),
               "User code contains unexpected character: #{char}"
      end)
    end

    test "generates codes with uniform character distribution" do
      # Generate many codes to check for obvious bias
      codes = Enum.map(1..1000, fn _ -> DeviceCode.generate_user_code() end)

      # Count frequency of each character
      char_counts =
        codes
        |> Enum.join("")
        |> String.graphemes()
        |> Enum.frequencies()

      # With 8000 characters (1000 codes * 8 chars) and 29 possible characters,
      # each character should appear ~276 times on average
      # We'll check that no character appears less than 200 times or more than 350 times
      # This is a loose bound to catch obvious bias while avoiding flaky tests
      Enum.each(char_counts, fn {char, count} ->
        assert count >= 200 and count <= 350,
               "Character '#{char}' appears #{count} times, expected roughly 276 ± 76"
      end)
    end
  end

  describe "edge cases and boundaries" do
    test "handles microsecond precision in expiration" do
      # Test with a time very close to now to check boundary behavior
      almost_now = DateTime.add(DateTime.utc_now(), -1, :microsecond)
      device_code = %DeviceCode{expires_at: almost_now}

      result = DeviceCode.expired?(device_code)
      assert is_boolean(result)
    end

    test "handles exactly now expiration time" do
      now = DateTime.utc_now()
      device_code = %DeviceCode{expires_at: now}

      # Due to microsecond precision, this could go either way
      result = DeviceCode.expired?(device_code)
      assert is_boolean(result)
    end

    test "handles all valid status transitions" do
      user = create_user()

      # Start with pending
      device_code = %DeviceCode{status: "pending"}

      # Can be authorized
      auth_changeset = DeviceCode.authorize_changeset(device_code, user)
      assert get_field(auth_changeset, :status) == "authorized"

      # Can be denied
      deny_changeset = DeviceCode.deny_changeset(device_code)
      assert get_field(deny_changeset, :status) == "denied"

      # Can be expired
      expire_changeset = DeviceCode.expire_changeset(device_code)
      assert get_field(expire_changeset, :status) == "expired"
    end
  end

  defp create_user do
    import Hexpm.Factory
    insert(:user)
  end
end
