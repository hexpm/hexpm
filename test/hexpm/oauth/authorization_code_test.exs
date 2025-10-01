defmodule Hexpm.OAuth.AuthorizationCodeTest do
  use Hexpm.DataCase, async: true

  import Ecto.Changeset, only: [get_field: 2]

  alias Hexpm.OAuth.{AuthorizationCode, Clients}

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
          client_id: Clients.generate_client_id(),
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
          client_id: Clients.generate_client_id(),
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
          client_id: Clients.generate_client_id(),
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

  describe "mark_as_used/1" do
    test "creates changeset with used_at timestamp" do
      auth_code = %AuthorizationCode{}
      changeset = AuthorizationCode.mark_as_used(auth_code)

      used_at = get_field(changeset, :used_at)
      assert used_at
      assert DateTime.diff(DateTime.utc_now(), used_at, :second) <= 1
    end
  end
end
