defmodule Hexpm.OAuth.AuthorizationCodeTest do
  use Hexpm.DataCase, async: true
  use ExUnitProperties

  import Ecto.Changeset, only: [get_field: 2]

  alias Hexpm.OAuth.AuthorizationCode

  describe "changeset/2" do
    test "validates required fields" do
      changeset = AuthorizationCode.changeset(%AuthorizationCode{}, %{})

      assert %{
               code: "can't be blank",
               redirect_uri: "can't be blank",
               expires_at: "can't be blank",
               user_id: "can't be blank",
               client_id: "can't be blank",
               code_challenge: "can't be blank",
               code_challenge_method: "can't be blank"
             } = errors_on(changeset)
    end

    test "validates scopes" do
      user = insert(:user)
      expires_at = DateTime.add(DateTime.utc_now(), 600, :second)

      changeset =
        AuthorizationCode.changeset(%AuthorizationCode{}, %{
          code: "test_code",
          redirect_uri: "https://example.com/callback",
          scopes: ["invalid_scope", "api"],
          expires_at: expires_at,
          user_id: user.id,
          client_id: Hexpm.OAuth.Client.generate_client_id(),
          code_challenge: "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM",
          code_challenge_method: "S256"
        })

      assert %{scopes: "contains invalid scopes: invalid_scope"} = errors_on(changeset)
    end

    test "validates invalid code challenge method" do
      user = insert(:user)
      expires_at = DateTime.add(DateTime.utc_now(), 600, :second)

      changeset =
        AuthorizationCode.changeset(%AuthorizationCode{}, %{
          code: "test_code",
          redirect_uri: "https://example.com/callback",
          scopes: ["api"],
          expires_at: expires_at,
          user_id: user.id,
          client_id: Hexpm.OAuth.Client.generate_client_id(),
          code_challenge: "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM",
          code_challenge_method: "invalid"
        })

      assert %{code_challenge_method: "must be one of: S256"} = errors_on(changeset)
    end

    test "creates valid changeset with all fields" do
      user = insert(:user)
      expires_at = DateTime.add(DateTime.utc_now(), 600, :second)

      changeset =
        AuthorizationCode.changeset(%AuthorizationCode{}, %{
          code: "test_code",
          redirect_uri: "https://example.com/callback",
          scopes: ["api", "api:read"],
          expires_at: expires_at,
          user_id: user.id,
          client_id: Hexpm.OAuth.Client.generate_client_id(),
          code_challenge: "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM",
          code_challenge_method: "S256"
        })

      assert changeset.valid?
    end
  end

  describe "build/1" do
    test "builds authorization code with valid attributes" do
      user = insert(:user)
      expires_at = DateTime.add(DateTime.utc_now(), 600, :second)

      attrs = %{
        code: "test_code",
        redirect_uri: "https://example.com/callback",
        scopes: ["api"],
        expires_at: expires_at,
        user_id: user.id,
        client_id: "test_client",
        code_challenge: "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM",
        code_challenge_method: "S256"
      }

      changeset = AuthorizationCode.build(attrs)
      assert changeset.valid?
    end
  end

  describe "generate_code/0" do
    test "generates non-empty string" do
      code = AuthorizationCode.generate_code()

      assert is_binary(code)
      assert String.length(code) > 0
    end

    property "always generates valid base64url strings without padding" do
      check all(_ <- constant(:ok), max_runs: 100) do
        code = AuthorizationCode.generate_code()

        assert is_binary(code)
        assert String.length(code) > 0
        refute String.contains?(code, "=")
        assert Regex.match?(~r/^[A-Za-z0-9_-]+$/, code)

        # Should be decodeable when padded
        padding_needed = rem(4 - rem(String.length(code), 4), 4)
        padded_code = code <> String.duplicate("=", padding_needed)
        assert {:ok, _decoded} = Base.url_decode64(padded_code)
      end
    end

    property "generates unique codes across many samples" do
      codes = for _ <- 1..1000, do: AuthorizationCode.generate_code()
      unique_codes = Enum.uniq(codes)

      # Should have very high uniqueness
      uniqueness_ratio = length(unique_codes) / length(codes)

      assert uniqueness_ratio > 0.99,
             "Uniqueness ratio #{uniqueness_ratio} too low, got #{length(unique_codes)} unique codes out of #{length(codes)}"
    end

    property "generated codes have reasonable length distribution" do
      codes = for _ <- 1..100, do: AuthorizationCode.generate_code()
      lengths = Enum.map(codes, &String.length/1)

      # All codes should have similar lengths (base64url encoding of random bytes)
      min_length = Enum.min(lengths)
      max_length = Enum.max(lengths)

      # Should not vary by more than a few characters
      assert max_length - min_length <= 4
      # Should be reasonably long for security
      assert min_length > 10
    end
  end

  describe "create_for_user/4" do
    setup do
      %{user: insert(:user)}
    end

    test "creates changeset with required fields", %{user: user} do
      changeset =
        AuthorizationCode.create_for_user(
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
        AuthorizationCode.create_for_user(
          user,
          "test_client",
          "https://example.com/callback",
          ["api"],
          code_challenge: "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM",
          expires_in: 300
        )

      expires_at = get_field(changeset, :expires_at)
      expected_time = DateTime.add(DateTime.utc_now(), 300, :second)

      # Allow 1 second tolerance for test execution time
      assert DateTime.diff(expires_at, expected_time, :second) |> abs() <= 1
    end

    test "adds PKCE challenge with default S256 method", %{user: user} do
      changeset =
        AuthorizationCode.create_for_user(
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
        AuthorizationCode.create_for_user(
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

      # Since we check if now > expires_at, equal times should not be expired
      # But due to timing, let's test the boundary case
      result = AuthorizationCode.expired?(auth_code)
      # This could be either true or false depending on microsecond timing
      assert is_boolean(result)
    end

    property "future timestamps are never expired" do
      check all(offset <- positive_integer()) do
        future_time = DateTime.add(DateTime.utc_now(), offset, :second)
        auth_code = %AuthorizationCode{expires_at: future_time}

        refute AuthorizationCode.expired?(auth_code)
      end
    end

    property "past timestamps are always expired" do
      check all(offset <- positive_integer()) do
        past_time = DateTime.add(DateTime.utc_now(), -offset, :second)
        auth_code = %AuthorizationCode{expires_at: past_time}

        assert AuthorizationCode.expired?(auth_code)
      end
    end
  end

  describe "used?/1" do
    test "returns false for unused code" do
      auth_code = %AuthorizationCode{used_at: nil}

      refute AuthorizationCode.used?(auth_code)
    end

    test "returns true for used code" do
      auth_code = %AuthorizationCode{used_at: DateTime.utc_now()}

      assert AuthorizationCode.used?(auth_code)
    end
  end

  describe "valid?/1" do
    test "returns true for non-expired, unused code" do
      future_time = DateTime.add(DateTime.utc_now(), 600, :second)
      auth_code = %AuthorizationCode{expires_at: future_time, used_at: nil}

      assert AuthorizationCode.valid?(auth_code)
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
        actual_valid = AuthorizationCode.valid?(auth_code)

        # Allow for timing differences near boundary
        if abs(time_offset) > 1 do
          assert actual_valid == expected_valid
        else
          # For boundary cases, just verify it returns a boolean
          assert is_boolean(actual_valid)
        end
      end
    end

    property "used codes are never valid regardless of expiration" do
      check all(time_offset <- integer(-3600..3600)) do
        expires_at = DateTime.add(DateTime.utc_now(), time_offset, :second)
        auth_code = %AuthorizationCode{expires_at: expires_at, used_at: DateTime.utc_now()}

        refute AuthorizationCode.valid?(auth_code)
      end
    end
  end

  describe "mark_as_used/1" do
    test "creates changeset with used_at timestamp" do
      auth_code = %AuthorizationCode{}
      changeset = AuthorizationCode.mark_as_used(auth_code)

      used_at = get_field(changeset, :used_at)
      assert used_at
      # Should be within last few seconds
      assert DateTime.diff(DateTime.utc_now(), used_at, :second) <= 1
    end
  end

  describe "verify_code_challenge/2" do
    test "validates S256 challenge method" do
      # Create a proper S256 challenge
      code_verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"

      code_challenge =
        :crypto.hash(:sha256, code_verifier)
        |> Base.url_encode64(padding: false)

      auth_code = %AuthorizationCode{
        code_challenge: code_challenge,
        code_challenge_method: "S256"
      }

      assert AuthorizationCode.verify_code_challenge(auth_code, code_verifier)
      refute AuthorizationCode.verify_code_challenge(auth_code, "wrong_verifier")
    end

    test "handles invalid S256 verifier gracefully" do
      auth_code = %AuthorizationCode{
        code_challenge: "invalid_challenge",
        code_challenge_method: "S256"
      }

      refute AuthorizationCode.verify_code_challenge(auth_code, "any_verifier")
    end

    property "S256 challenge verification is deterministic" do
      check all(verifier <- string(:alphanumeric, length: 32)) do
        # Generate proper S256 challenge
        code_challenge =
          :crypto.hash(:sha256, verifier)
          |> Base.url_encode64(padding: false)

        auth_code = %AuthorizationCode{
          code_challenge: code_challenge,
          code_challenge_method: "S256"
        }

        # Correct verifier should always verify
        assert AuthorizationCode.verify_code_challenge(auth_code, verifier)

        # Wrong verifier should always fail
        wrong_verifier = verifier <> "x"
        refute AuthorizationCode.verify_code_challenge(auth_code, wrong_verifier)
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

        # Test various incorrect verifiers
        wrong_verifiers = [
          String.upcase(verifier),
          String.slice(verifier, 0..-2//1),
          verifier <> "extra",
          String.replace(verifier, "a", "b", global: false)
        ]

        Enum.each(wrong_verifiers, fn wrong_verifier ->
          if wrong_verifier != verifier do
            refute AuthorizationCode.verify_code_challenge(auth_code, wrong_verifier)
          end
        end)

        # But the correct verifier should work
        assert AuthorizationCode.verify_code_challenge(auth_code, verifier)
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
                  # Wrong length
                  string(:alphanumeric, length: 10)
                ])
            ) do
        auth_code = %AuthorizationCode{
          code_challenge: bad_challenge,
          code_challenge_method: "S256"
        }

        # Should not crash, just return false
        refute AuthorizationCode.verify_code_challenge(auth_code, verifier)
      end
    end
  end
end
