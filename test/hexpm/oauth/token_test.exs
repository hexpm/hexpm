defmodule Hexpm.OAuth.TokenTest do
  use Hexpm.DataCase, async: true

  alias Hexpm.OAuth.{Token, Clients, Sessions}

  describe "changeset/2" do
    test "validates required fields" do
      changeset = Token.changeset(%Token{}, %{})

      assert %{
               jti: "can't be blank",
               expires_at: "can't be blank",
               grant_type: "can't be blank",
               user_id: "can't be blank",
               client_id: "can't be blank"
             } = errors_on(changeset)
    end

    test "validates grant type inclusion" do
      user = insert(:user)
      expires_at = DateTime.add(DateTime.utc_now(), 3600, :second)

      changeset =
        Token.changeset(%Token{}, %{
          jti: "test-jti-123",
          token_type: "bearer",
          scopes: ["api"],
          expires_at: expires_at,
          grant_type: "invalid_grant",
          user_id: user.id,
          client_id: Clients.generate_client_id()
        })

      assert %{grant_type: "is invalid"} = errors_on(changeset)
    end

    test "validates scopes" do
      user = insert(:user)
      expires_at = DateTime.add(DateTime.utc_now(), 3600, :second)

      changeset =
        Token.changeset(%Token{}, %{
          jti: "test-jti-456",
          token_type: "bearer",
          scopes: ["invalid_scope", "api"],
          expires_at: expires_at,
          grant_type: "authorization_code",
          user_id: user.id,
          client_id: Clients.generate_client_id()
        })

      assert %{scopes: "contains invalid scopes: invalid_scope"} = errors_on(changeset)
    end

    test "creates valid changeset with all fields" do
      user = insert(:user)
      client = insert(:oauth_client)
      {:ok, session} = Sessions.create_for_user(user, client.client_id)
      expires_at = DateTime.add(DateTime.utc_now(), 3600, :second)

      attrs = %{
        jti: "test-jti-789",
        token_type: "bearer",
        refresh_jti: "refresh-jti-123",
        scopes: ["api", "api:read"],
        expires_at: expires_at,
        grant_type: "authorization_code",
        grant_reference: "auth_code_123",
        user_id: user.id,
        client_id: client.client_id,
        session_id: session.id
      }

      changeset = Token.changeset(%Token{}, attrs)
      assert changeset.valid?
    end
  end

  describe "build/1" do
    test "builds token with valid attributes" do
      user = insert(:user)
      client = insert(:oauth_client)
      {:ok, session} = Sessions.create_for_user(user, client.client_id)
      expires_at = DateTime.add(DateTime.utc_now(), 3600, :second)

      attrs = %{
        jti: "test-jti-build",
        token_type: "bearer",
        scopes: ["api"],
        expires_at: expires_at,
        grant_type: "authorization_code",
        user_id: user.id,
        client_id: client.client_id,
        session_id: session.id
      }

      changeset = Token.build(attrs)
      assert changeset.valid?
    end
  end
end
