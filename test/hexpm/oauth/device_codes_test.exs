defmodule Hexpm.OAuth.DeviceCodesTest do
  use Hexpm.DataCase, async: true
  use ExUnitProperties

  alias Hexpm.OAuth.{DeviceCode, DeviceCodes}

  describe "expired?/1" do
    property "future timestamps are never expired" do
      check all(offset <- positive_integer()) do
        future_time = DateTime.add(DateTime.utc_now(), offset, :second)
        device_code = %DeviceCode{expires_at: future_time}

        refute DeviceCodes.expired?(device_code)
      end
    end

    property "past timestamps are always expired" do
      check all(offset <- positive_integer()) do
        past_time = DateTime.add(DateTime.utc_now(), -offset, :second)
        device_code = %DeviceCode{expires_at: past_time}

        assert DeviceCodes.expired?(device_code)
      end
    end

    property "expiration is consistent with DateTime.compare" do
      check all(offset <- integer(-86400..86400)) do
        test_time = DateTime.add(DateTime.utc_now(), offset, :second)
        device_code = %DeviceCode{expires_at: test_time}

        expected_expired = DateTime.compare(test_time, DateTime.utc_now()) == :lt
        actual_expired = DeviceCodes.expired?(device_code)

        if abs(offset) > 1 do
          assert actual_expired == expected_expired
        else
          assert is_boolean(actual_expired)
        end
      end
    end
  end

  describe "pending?/1" do
    test "returns true for pending, non-expired device code" do
      future_time = DateTime.add(DateTime.utc_now(), 600, :second)
      device_code = %DeviceCode{status: "pending", expires_at: future_time}

      assert DeviceCodes.pending?(device_code)
    end

    test "returns false for pending but expired device code" do
      past_time = DateTime.add(DateTime.utc_now(), -600, :second)
      device_code = %DeviceCode{status: "pending", expires_at: past_time}

      refute DeviceCodes.pending?(device_code)
    end

    test "returns false for non-pending device code" do
      future_time = DateTime.add(DateTime.utc_now(), 600, :second)
      device_code = %DeviceCode{status: "authorized", expires_at: future_time}

      refute DeviceCodes.pending?(device_code)
    end

    property "pending requires both 'pending' status and non-expired time" do
      check all(
              status <- member_of(["pending", "authorized", "denied", "expired"]),
              offset <- integer(-3600..3600)
            ) do
        expires_at = DateTime.add(DateTime.utc_now(), offset, :second)
        device_code = %DeviceCode{status: status, expires_at: expires_at}

        expected_pending = status == "pending" && offset > 0
        actual_pending = DeviceCodes.pending?(device_code)

        if abs(offset) > 1 do
          assert actual_pending == expected_pending
        else
          assert is_boolean(actual_pending)
        end
      end
    end

    property "non-pending statuses are never pending regardless of expiration" do
      check all(
              status <- member_of(["authorized", "denied", "expired"]),
              offset <- integer(-3600..3600)
            ) do
        expires_at = DateTime.add(DateTime.utc_now(), offset, :second)
        device_code = %DeviceCode{status: status, expires_at: expires_at}

        refute DeviceCodes.pending?(device_code)
      end
    end
  end

  describe "authorized?/1" do
    test "returns true for authorized device code" do
      device_code = %DeviceCode{status: "authorized"}

      assert DeviceCodes.authorized?(device_code)
    end

    test "returns false for non-authorized device code" do
      device_code = %DeviceCode{status: "pending"}

      refute DeviceCodes.authorized?(device_code)
    end
  end

  describe "denied?/1" do
    test "returns true for denied device code" do
      device_code = %DeviceCode{status: "denied"}

      assert DeviceCodes.denied?(device_code)
    end

    test "returns false for non-denied device code" do
      device_code = %DeviceCode{status: "pending"}

      refute DeviceCodes.denied?(device_code)
    end
  end

  describe "generate_device_code/0" do
    test "generates non-empty string" do
      device_code = DeviceCodes.generate_device_code()

      assert is_binary(device_code)
      assert String.length(device_code) > 0
    end

    property "always generates 32-character base64url strings" do
      check all(_ <- constant(:ok), max_runs: 100) do
        device_code = DeviceCodes.generate_device_code()

        assert String.length(device_code) == 32
        refute String.contains?(device_code, "=")
        assert Regex.match?(~r/^[A-Za-z0-9_-]+$/, device_code)
        assert is_binary(device_code)
      end
    end

    property "generates unique device codes across many samples" do
      check all(_ <- constant(:ok)) do
        codes = for _ <- 1..1000, do: DeviceCodes.generate_device_code()
        unique_codes = Enum.uniq(codes)

        assert length(codes) == length(unique_codes)
      end
    end

    property "generated codes are valid base64url when padded" do
      check all(_ <- constant(:ok), max_runs: 50) do
        device_code = DeviceCodes.generate_device_code()

        padding_needed = rem(4 - rem(String.length(device_code), 4), 4)
        padded_code = device_code <> String.duplicate("=", padding_needed)

        assert {:ok, _decoded} = Base.url_decode64(padded_code)
      end
    end
  end

  describe "generate_user_code/0" do
    test "generates non-empty string" do
      user_code = DeviceCodes.generate_user_code()

      assert is_binary(user_code)
      assert String.length(user_code) > 0
    end

    property "always generates 8-character codes from allowed charset" do
      check all(_ <- constant(:ok), max_runs: 100) do
        user_code = DeviceCodes.generate_user_code()

        assert String.length(user_code) == 8
        assert String.match?(user_code, ~r/^[23456789BCDFGHJKLMNPQRSTVWXYZ]{8}$/)
        assert is_binary(user_code)
      end
    end

    property "never generates codes with forbidden characters" do
      check all(_ <- constant(:ok), max_runs: 100) do
        user_code = DeviceCodes.generate_user_code()

        forbidden_chars = ["0", "1", "I", "O", "A", "E", "U"]

        Enum.each(forbidden_chars, fn char ->
          refute String.contains?(user_code, char),
                 "User code '#{user_code}' contains forbidden character: #{char}"
        end)
      end
    end

    property "generates unique user codes across many samples" do
      check all(_ <- constant(:ok)) do
        codes = for _ <- 1..1000, do: DeviceCodes.generate_user_code()
        unique_codes = Enum.uniq(codes)

        uniqueness_ratio = length(unique_codes) / length(codes)

        assert uniqueness_ratio > 0.99,
               "Uniqueness ratio #{uniqueness_ratio} too low, got #{length(unique_codes)} unique codes out of #{length(codes)}"
      end
    end

    property "character distribution is reasonably uniform across large samples" do
      check all(_ <- constant(:ok)) do
        codes = for _ <- 1..500, do: DeviceCodes.generate_user_code()
        all_chars = codes |> Enum.join("") |> String.graphemes()
        char_counts = Enum.frequencies(all_chars)

        allowed_charset = String.graphemes("23456789BCDFGHJKLMNPQRSTVWXYZ")
        total_chars = length(all_chars)
        expected_per_char = total_chars / length(allowed_charset)

        Enum.each(char_counts, fn {char, count} ->
          ratio = count / expected_per_char

          assert ratio >= 0.6 and ratio <= 1.4,
                 "Character '#{char}' appears #{count} times (ratio: #{ratio}), expected around #{expected_per_char}"
        end)
      end
    end
  end

  describe "edge cases and boundaries" do
    test "handles microsecond precision in expiration" do
      almost_now = DateTime.add(DateTime.utc_now(), -1, :microsecond)
      device_code = %DeviceCode{expires_at: almost_now}

      result = DeviceCodes.expired?(device_code)
      assert is_boolean(result)
    end

    test "handles exactly now expiration time" do
      now = DateTime.utc_now()
      device_code = %DeviceCode{expires_at: now}

      result = DeviceCodes.expired?(device_code)
      assert is_boolean(result)
    end
  end
end
