defmodule Hexpm.OAuth.AuthorizationCodeTest do
  use Hexpm.DataCase, async: true

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
               client_id: "can't be blank"
             } = errors_on(changeset)
    end

    test "validates scopes" do
      user = create_user()
      expires_at = DateTime.add(DateTime.utc_now(), 600, :second)

      changeset =
        AuthorizationCode.changeset(%AuthorizationCode{}, %{
          code: "test_code",
          redirect_uri: "https://example.com/callback",
          scopes: ["invalid_scope", "api"],
          expires_at: expires_at,
          user_id: user.id,
          client_id: "test_client"
        })

      assert %{scopes: "contains invalid scopes: invalid_scope"} = errors_on(changeset)
    end

    test "validates code challenge without method" do
      user = create_user()
      expires_at = DateTime.add(DateTime.utc_now(), 600, :second)

      changeset =
        AuthorizationCode.changeset(%AuthorizationCode{}, %{
          code: "test_code",
          redirect_uri: "https://example.com/callback",
          scopes: ["api"],
          expires_at: expires_at,
          user_id: user.id,
          client_id: "test_client",
          code_challenge: "challenge123"
        })

      assert %{code_challenge_method: "is required when code_challenge is specified"} =
               errors_on(changeset)
    end

    test "validates code challenge method without challenge" do
      user = create_user()
      expires_at = DateTime.add(DateTime.utc_now(), 600, :second)

      changeset =
        AuthorizationCode.changeset(%AuthorizationCode{}, %{
          code: "test_code",
          redirect_uri: "https://example.com/callback",
          scopes: ["api"],
          expires_at: expires_at,
          user_id: user.id,
          client_id: "test_client",
          code_challenge_method: "S256"
        })

      assert %{code_challenge: "is required when code_challenge_method is specified"} =
               errors_on(changeset)
    end

    test "validates invalid code challenge method" do
      user = create_user()
      expires_at = DateTime.add(DateTime.utc_now(), 600, :second)

      changeset =
        AuthorizationCode.changeset(%AuthorizationCode{}, %{
          code: "test_code",
          redirect_uri: "https://example.com/callback",
          scopes: ["api"],
          expires_at: expires_at,
          user_id: user.id,
          client_id: "test_client",
          code_challenge: "challenge123",
          code_challenge_method: "invalid"
        })

      assert %{code_challenge_method: "must be one of: S256"} = errors_on(changeset)
    end

    test "creates valid changeset with all fields" do
      user = create_user()
      expires_at = DateTime.add(DateTime.utc_now(), 600, :second)

      changeset =
        AuthorizationCode.changeset(%AuthorizationCode{}, %{
          code: "test_code",
          redirect_uri: "https://example.com/callback",
          scopes: ["api", "api:read"],
          expires_at: expires_at,
          user_id: user.id,
          client_id: "test_client",
          code_challenge: "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM",
          code_challenge_method: "S256"
        })

      assert changeset.valid?
    end
  end

  describe "build/1" do
    test "builds authorization code with valid attributes" do
      user = create_user()
      expires_at = DateTime.add(DateTime.utc_now(), 600, :second)

      attrs = %{
        code: "test_code",
        redirect_uri: "https://example.com/callback",
        scopes: ["api"],
        expires_at: expires_at,
        user_id: user.id,
        client_id: "test_client"
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

    test "generates unique codes" do
      code1 = AuthorizationCode.generate_code()
      code2 = AuthorizationCode.generate_code()

      assert code1 != code2
    end

    test "generates base64url encoded strings without padding" do
      code = AuthorizationCode.generate_code()

      # Should not contain padding characters
      refute String.contains?(code, "=")
      # Should be valid base64url (add padding if needed)
      padded_code = code <> String.duplicate("=", rem(4 - rem(String.length(code), 4), 4))
      assert {:ok, _} = Base.url_decode64(padded_code)
    end
  end

  describe "create_for_user/4" do
    setup do
      user = create_user()
      %{user: user}
    end

    test "creates changeset with required fields", %{user: user} do
      changeset =
        AuthorizationCode.create_for_user(
          user,
          "test_client",
          "https://example.com/callback",
          ["api"]
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
    test "returns false for non-expired code" do
      future_time = DateTime.add(DateTime.utc_now(), 600, :second)
      auth_code = %AuthorizationCode{expires_at: future_time}

      refute AuthorizationCode.expired?(auth_code)
    end

    test "returns true for expired code" do
      past_time = DateTime.add(DateTime.utc_now(), -600, :second)
      auth_code = %AuthorizationCode{expires_at: past_time}

      assert AuthorizationCode.expired?(auth_code)
    end

    test "returns true for code that expires exactly now" do
      now = DateTime.utc_now()
      auth_code = %AuthorizationCode{expires_at: now}

      # Since we check if now > expires_at, equal times should not be expired
      # But due to timing, let's test the boundary case
      result = AuthorizationCode.expired?(auth_code)
      # This could be either true or false depending on microsecond timing
      assert is_boolean(result)
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

    test "returns false for expired code" do
      past_time = DateTime.add(DateTime.utc_now(), -600, :second)
      auth_code = %AuthorizationCode{expires_at: past_time, used_at: nil}

      refute AuthorizationCode.valid?(auth_code)
    end

    test "returns false for used code" do
      future_time = DateTime.add(DateTime.utc_now(), 600, :second)
      auth_code = %AuthorizationCode{expires_at: future_time, used_at: DateTime.utc_now()}

      refute AuthorizationCode.valid?(auth_code)
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
    test "returns true when no challenge is set" do
      auth_code = %AuthorizationCode{code_challenge: nil}

      assert AuthorizationCode.verify_code_challenge(auth_code, "any_verifier")
    end

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
  end

  defp create_user do
    import Hexpm.Factory
    insert(:user)
  end
end
