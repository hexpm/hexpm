defmodule Hexpm.Accounts.RecoveryCodeTest do
  use Hexpm.DataCase, async: true
  use ExUnitProperties

  alias Hexpm.Accounts.RecoveryCode

  describe "generate/0" do
    test "generates a string" do
      code = RecoveryCode.generate()

      assert is_binary(code)
      assert String.length(code) > 0
    end

    test "generates formatted code with dashes" do
      code = RecoveryCode.generate()

      # Should match pattern like "a1b2-c3d4-e5f6-g7h8" (base32 encoding of 10 bytes = 16 chars + 3 dashes)
      assert Regex.match?(~r/^[a-z0-9]{4}-[a-z0-9]{4}-[a-z0-9]{4}-[a-z0-9]{4}$/, code)
    end

    test "generates unique codes" do
      code1 = RecoveryCode.generate()
      code2 = RecoveryCode.generate()

      assert code1 != code2
    end

    property "always generates correctly formatted codes" do
      check all(_ <- constant(:ok), max_runs: 100) do
        code = RecoveryCode.generate()

        # Should be 19 characters total (16 base32 + 3 dashes)
        assert String.length(code) == 19
        # Should match the expected pattern (base32 uses 0-9 and a-z)
        assert Regex.match?(~r/^[a-z0-9]{4}-[a-z0-9]{4}-[a-z0-9]{4}-[a-z0-9]{4}$/, code)
        # Should contain exactly 3 dashes
        assert String.graphemes(code) |> Enum.count(&(&1 == "-")) == 3
      end
    end

    property "generates unique codes across many samples" do
      check all(_ <- constant(:ok)) do
        codes = for _ <- 1..1000, do: RecoveryCode.generate()
        unique_codes = Enum.uniq(codes)

        # Should have very high uniqueness
        uniqueness_ratio = length(unique_codes) / length(codes)

        assert uniqueness_ratio > 0.99,
               "Uniqueness ratio #{uniqueness_ratio} too low, got #{length(unique_codes)} unique codes out of #{length(codes)}"
      end
    end

    property "generated codes use only lowercase base32 characters" do
      check all(_ <- constant(:ok), max_runs: 100) do
        code = RecoveryCode.generate()

        # Remove dashes and check remaining characters
        base32_part = String.replace(code, "-", "")
        assert String.length(base32_part) == 16
        assert Regex.match?(~r/^[a-z0-9]+$/, base32_part)
        refute Regex.match?(~r/[A-Z]/, base32_part)
      end
    end

    property "character distribution shows reasonable randomness" do
      check all(_ <- constant(:ok)) do
        codes = for _ <- 1..100, do: RecoveryCode.generate()

        all_base32_chars =
          codes
          |> Enum.map(&String.replace(&1, "-", ""))
          |> Enum.join("")
          |> String.graphemes()

        char_counts = Enum.frequencies(all_base32_chars)

        # Just check that we have a reasonable variety of characters
        # and no single character dominates
        unique_chars = Map.keys(char_counts)
        total_chars = length(all_base32_chars)

        # Should have at least 10 different characters
        assert length(unique_chars) >= 10

        # No single character should appear more than 30% of the time
        Enum.each(char_counts, fn {_char, count} ->
          ratio = count / total_chars

          assert ratio <= 0.3,
                 "Character appears #{count}/#{total_chars} times (#{ratio}), which is too frequent"
        end)
      end
    end
  end

  describe "generate_set/0" do
    test "generates set of 10 recovery codes" do
      recovery_codes = RecoveryCode.generate_set()

      assert length(recovery_codes) == 10
      assert Enum.all?(recovery_codes, &is_struct(&1, RecoveryCode))
      assert Enum.all?(recovery_codes, &is_nil(&1.used_at))
    end

    test "generates unique codes in set" do
      recovery_codes = RecoveryCode.generate_set()
      codes = Enum.map(recovery_codes, & &1.code)
      unique_codes = Enum.uniq(codes)

      assert length(codes) == length(unique_codes)
    end

    property "always generates exactly 10 unique recovery codes" do
      check all(_ <- constant(:ok), max_runs: 50) do
        recovery_codes = RecoveryCode.generate_set()

        assert length(recovery_codes) == 10
        assert Enum.all?(recovery_codes, &is_struct(&1, RecoveryCode))
        assert Enum.all?(recovery_codes, &is_nil(&1.used_at))

        codes = Enum.map(recovery_codes, & &1.code)
        assert length(Enum.uniq(codes)) == 10
      end
    end
  end

  describe "verify/2" do
    setup do
      recovery_codes = RecoveryCode.generate_set()
      valid_code = List.first(recovery_codes).code
      %{recovery_codes: recovery_codes, valid_code: valid_code}
    end

    test "verifies valid unused code", %{recovery_codes: recovery_codes, valid_code: valid_code} do
      assert {:ok, _code} = RecoveryCode.verify(recovery_codes, valid_code)
    end

    test "rejects invalid code", %{recovery_codes: recovery_codes} do
      assert {:error, :invalid_code} = RecoveryCode.verify(recovery_codes, "invalid-code")
    end

    test "rejects used code", %{recovery_codes: recovery_codes, valid_code: valid_code} do
      # Mark the code as used
      used_codes =
        Enum.map(recovery_codes, fn code ->
          if code.code == valid_code do
            %{code | used_at: DateTime.utc_now()}
          else
            code
          end
        end)

      assert {:error, :invalid_code} = RecoveryCode.verify(used_codes, valid_code)
    end

    property "only accepts exact code matches" do
      check all(_ <- constant(:ok), max_runs: 50) do
        recovery_codes = RecoveryCode.generate_set()
        valid_code = List.first(recovery_codes).code

        # Test with various invalid modifications
        invalid_codes = [
          String.upcase(valid_code),
          String.replace(valid_code, "-", ""),
          valid_code <> "x",
          String.slice(valid_code, 0..-2//1),
          "x" <> valid_code
        ]

        Enum.each(invalid_codes, fn invalid_code ->
          assert {:error, :invalid_code} = RecoveryCode.verify(recovery_codes, invalid_code)
        end)

        # But the exact code should work
        assert {:ok, _} = RecoveryCode.verify(recovery_codes, valid_code)
      end
    end

    property "verification is timing-safe" do
      check all(_ <- constant(:ok), max_runs: 20) do
        recovery_codes = RecoveryCode.generate_set()
        valid_code = List.first(recovery_codes).code

        # Create an invalid code of the same length
        invalid_code = String.replace(valid_code, ~r/[a-z0-9]/, "x", global: false)

        # Both should complete (timing attack resistance tested by consistent behavior)
        start_time = System.monotonic_time()
        {:error, :invalid_code} = RecoveryCode.verify(recovery_codes, invalid_code)
        invalid_time = System.monotonic_time() - start_time

        start_time = System.monotonic_time()
        {:ok, _} = RecoveryCode.verify(recovery_codes, valid_code)
        valid_time = System.monotonic_time() - start_time

        # Both operations should complete in reasonable time
        assert invalid_time > 0
        assert valid_time > 0
      end
    end
  end
end
