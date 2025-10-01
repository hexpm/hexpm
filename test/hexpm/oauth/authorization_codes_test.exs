defmodule Hexpm.OAuth.AuthorizationCodesTest do
  use Hexpm.DataCase, async: true
  use ExUnitProperties

  import Ecto.Changeset, only: [get_field: 2]

  alias Hexpm.OAuth.{AuthorizationCode, AuthorizationCodes}

  describe "code generation" do
    test "generates non-empty string through create_for_user" do
      user = insert(:user)

      changeset =
        AuthorizationCodes.create_for_user(
          user,
          "test_client",
          "https://example.com/callback",
          ["api"],
          code_challenge: "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
        )

      code = get_field(changeset, :code)

      assert is_binary(code)
      assert String.length(code) > 0
    end

    property "always generates valid base64url strings without padding" do
      check all(_ <- constant(:ok), max_runs: 100) do
        user = insert(:user)

        changeset =
          AuthorizationCodes.create_for_user(
            user,
            "test_client",
            "https://example.com/callback",
            ["api"],
            code_challenge: "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
          )

        code = get_field(changeset, :code)

        assert is_binary(code)
        assert String.length(code) > 0
        refute String.contains?(code, "=")
        assert Regex.match?(~r/^[A-Za-z0-9_-]+$/, code)

        padding_needed = rem(4 - rem(String.length(code), 4), 4)
        padded_code = code <> String.duplicate("=", padding_needed)
        assert {:ok, _decoded} = Base.url_decode64(padded_code)
      end
    end

    property "generates unique codes across many samples" do
      check all(_ <- constant(:ok)) do
        user = insert(:user)

        codes =
          for _ <- 1..1000 do
            changeset =
              AuthorizationCodes.create_for_user(
                user,
                "test_client",
                "https://example.com/callback",
                ["api"],
                code_challenge: "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
              )

            get_field(changeset, :code)
          end

        unique_codes = Enum.uniq(codes)

        uniqueness_ratio = length(unique_codes) / length(codes)

        assert uniqueness_ratio > 0.99,
               "Uniqueness ratio #{uniqueness_ratio} too low, got #{length(unique_codes)} unique codes out of #{length(codes)}"
      end
    end

    property "generated codes have reasonable length distribution" do
      check all(_ <- constant(:ok)) do
        user = insert(:user)

        codes =
          for _ <- 1..100 do
            changeset =
              AuthorizationCodes.create_for_user(
                user,
                "test_client",
                "https://example.com/callback",
                ["api"],
                code_challenge: "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
              )

            get_field(changeset, :code)
          end

        lengths = Enum.map(codes, &String.length/1)

        min_length = Enum.min(lengths)
        max_length = Enum.max(lengths)

        assert max_length - min_length <= 4
        assert min_length > 10
      end
    end
  end

  describe "create_for_user/4" do
    setup do
      %{user: insert(:user)}
    end

    test "creates changeset with required fields", %{user: user} do
      changeset =
        AuthorizationCodes.create_for_user(
          user,
          "test_client",
          "https://example.com/callback",
          ["api"],
          code_challenge: "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
        )

      assert changeset.valid?
      assert get_field(changeset, :code)
      assert get_field(changeset, :redirect_uri) == "https://example.com/callback"
      assert get_field(changeset, :scopes) == ["api"]
      assert get_field(changeset, :user_id) == user.id
      assert get_field(changeset, :client_id) == "test_client"
      assert get_field(changeset, :expires_at)
    end

    test "sets custom expiration time", %{user: user} do
      changeset =
        AuthorizationCodes.create_for_user(
          user,
          "test_client",
          "https://example.com/callback",
          ["api"],
          code_challenge: "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM",
          expires_in: 300
        )

      expires_at = get_field(changeset, :expires_at)
      expected_time = DateTime.add(DateTime.utc_now(), 300, :second)

      assert DateTime.diff(expires_at, expected_time, :second) |> abs() <= 1
    end

    test "adds PKCE challenge with default S256 method", %{user: user} do
      changeset =
        AuthorizationCodes.create_for_user(
          user,
          "test_client",
          "https://example.com/callback",
          ["api"],
          code_challenge: "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
        )

      assert get_field(changeset, :code_challenge) ==
               "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"

      assert get_field(changeset, :code_challenge_method) == "S256"
    end

    test "adds PKCE challenge with explicit S256 method", %{user: user} do
      changeset =
        AuthorizationCodes.create_for_user(
          user,
          "test_client",
          "https://example.com/callback",
          ["api"],
          code_challenge: "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM",
          code_challenge_method: "S256"
        )

      assert get_field(changeset, :code_challenge) ==
               "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"

      assert get_field(changeset, :code_challenge_method) == "S256"
    end
  end

  describe "expired?/1" do
    test "returns true for code that expires exactly now" do
      now = DateTime.utc_now()
      auth_code = %AuthorizationCode{expires_at: now}

      result = AuthorizationCodes.expired?(auth_code)
      assert is_boolean(result)
    end

    property "future timestamps are never expired" do
      check all(offset <- positive_integer()) do
        future_time = DateTime.add(DateTime.utc_now(), offset, :second)
        auth_code = %AuthorizationCode{expires_at: future_time}

        refute AuthorizationCodes.expired?(auth_code)
      end
    end

    property "past timestamps are always expired" do
      check all(offset <- positive_integer()) do
        past_time = DateTime.add(DateTime.utc_now(), -offset, :second)
        auth_code = %AuthorizationCode{expires_at: past_time}

        assert AuthorizationCodes.expired?(auth_code)
      end
    end
  end

  describe "used?/1" do
    test "returns false for unused code" do
      auth_code = %AuthorizationCode{used_at: nil}

      refute AuthorizationCodes.used?(auth_code)
    end

    test "returns true for used code" do
      auth_code = %AuthorizationCode{used_at: DateTime.utc_now()}

      assert AuthorizationCodes.used?(auth_code)
    end
  end

  describe "valid?/1" do
    test "returns true for non-expired, unused code" do
      future_time = DateTime.add(DateTime.utc_now(), 600, :second)
      auth_code = %AuthorizationCode{expires_at: future_time, used_at: nil}

      assert AuthorizationCodes.valid?(auth_code)
    end

    property "validity requires both non-expired and unused state" do
      check all(
              time_offset <- integer(-3600..3600),
              used <- boolean()
            ) do
        expires_at = DateTime.add(DateTime.utc_now(), time_offset, :second)
        used_at = if used, do: DateTime.utc_now(), else: nil

        auth_code = %AuthorizationCode{expires_at: expires_at, used_at: used_at}

        expected_valid = time_offset > 0 && !used
        actual_valid = AuthorizationCodes.valid?(auth_code)

        if abs(time_offset) > 1 do
          assert actual_valid == expected_valid
        else
          assert is_boolean(actual_valid)
        end
      end
    end

    property "used codes are never valid regardless of expiration" do
      check all(time_offset <- integer(-3600..3600)) do
        expires_at = DateTime.add(DateTime.utc_now(), time_offset, :second)
        auth_code = %AuthorizationCode{expires_at: expires_at, used_at: DateTime.utc_now()}

        refute AuthorizationCodes.valid?(auth_code)
      end
    end
  end

  describe "verify_code_challenge/2" do
    test "validates S256 challenge method" do
      code_verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"

      code_challenge =
        :crypto.hash(:sha256, code_verifier)
        |> Base.url_encode64(padding: false)

      auth_code = %AuthorizationCode{
        code_challenge: code_challenge,
        code_challenge_method: "S256"
      }

      assert AuthorizationCodes.verify_code_challenge(auth_code, code_verifier)
      refute AuthorizationCodes.verify_code_challenge(auth_code, "wrong_verifier")
    end

    test "handles invalid S256 verifier gracefully" do
      auth_code = %AuthorizationCode{
        code_challenge: "invalid_challenge",
        code_challenge_method: "S256"
      }

      refute AuthorizationCodes.verify_code_challenge(auth_code, "any_verifier")
    end

    property "S256 challenge verification is deterministic" do
      check all(verifier <- string(:alphanumeric, length: 32)) do
        code_challenge =
          :crypto.hash(:sha256, verifier)
          |> Base.url_encode64(padding: false)

        auth_code = %AuthorizationCode{
          code_challenge: code_challenge,
          code_challenge_method: "S256"
        }

        assert AuthorizationCodes.verify_code_challenge(auth_code, verifier)

        wrong_verifier = verifier <> "x"
        refute AuthorizationCodes.verify_code_challenge(auth_code, wrong_verifier)
      end
    end

    property "only exact verifier matches succeed" do
      check all(verifier <- string(:alphanumeric, length: 32)) do
        code_challenge =
          :crypto.hash(:sha256, verifier)
          |> Base.url_encode64(padding: false)

        auth_code = %AuthorizationCode{
          code_challenge: code_challenge,
          code_challenge_method: "S256"
        }

        wrong_verifiers = [
          String.upcase(verifier),
          String.slice(verifier, 0..-2//1),
          verifier <> "extra",
          String.replace(verifier, "a", "b", global: false)
        ]

        Enum.each(wrong_verifiers, fn wrong_verifier ->
          if wrong_verifier != verifier do
            refute AuthorizationCodes.verify_code_challenge(auth_code, wrong_verifier)
          end
        end)

        assert AuthorizationCodes.verify_code_challenge(auth_code, verifier)
      end
    end

    property "verification fails gracefully with malformed challenges" do
      check all(
              verifier <- string(:alphanumeric, length: 32),
              bad_challenge <-
                one_of([
                  constant("not_base64_!@#"),
                  constant(""),
                  constant("too_short"),
                  string(:alphanumeric, length: 10)
                ])
            ) do
        auth_code = %AuthorizationCode{
          code_challenge: bad_challenge,
          code_challenge_method: "S256"
        }

        refute AuthorizationCodes.verify_code_challenge(auth_code, verifier)
      end
    end
  end
end
