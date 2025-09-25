defmodule HexpmWeb.OAuthControllerTest do
  use HexpmWeb.ConnCase, async: true

  alias Hexpm.OAuth.{Client, Clients}
  import Hexpm.Factory

  defp login_user(conn, user) do
    conn
    |> init_test_session(%{})
    |> put_session("user_id", user.id)
  end

  defp create_test_client(name \\ "Test OAuth App") do
    client_params = %{
      client_id: Clients.generate_client_id(),
      name: name,
      client_type: "confidential",
      allowed_grant_types: ["authorization_code"],
      allowed_scopes: ["api", "api:read", "api:write", "repositories"],
      redirect_uris: ["https://example.com/callback"],
      client_secret: Clients.generate_client_secret()
    }

    {:ok, client} = Client.build(client_params) |> Repo.insert()
    client
  end

  describe "GET /oauth/authorize" do
    setup do
      client = create_test_client()
      %{client: client}
    end

    test "redirects to login when not authenticated", %{client: client} do
      conn =
        get(build_conn(), ~p"/oauth/authorize", %{
          "client_id" => client.client_id,
          "redirect_uri" => "https://example.com/callback",
          "scope" => "api:read",
          "code_challenge" => "challenge123",
          "code_challenge_method" => "S256"
        })

      assert redirected_to(conn) =~ "/login"
    end

    @tag :skip
    test "shows authorization page when authenticated", %{client: client} do
      user = insert(:user)
      conn = login_user(build_conn(), user)

      conn =
        get(conn, ~p"/oauth/authorize", %{
          "client_id" => client.client_id,
          "redirect_uri" => "https://example.com/callback",
          "scope" => "api:read repositories",
          "code_challenge" => "challenge123",
          "code_challenge_method" => "S256"
        })

      html = html_response(conn, 200)
      assert html =~ "Authorize Application"
      assert html =~ client.name
      assert html =~ "api:read"
      assert html =~ "repositories"
      assert html =~ "Select All"
      assert html =~ "Deselect All"
    end
  end

  describe "POST /oauth/authorize (consent)" do
    setup do
      client = create_test_client()
      user = insert(:user)
      %{client: client, user: user}
    end

    test "returns error when no selected_scopes provided", %{client: client, user: user} do
      conn = login_user(build_conn(), user)

      conn =
        post(conn, ~p"/oauth/authorize", %{
          "client_id" => client.client_id,
          "redirect_uri" => "https://example.com/callback",
          "scope" => "api:read repositories",
          "code_challenge" => "challenge123",
          "code_challenge_method" => "S256",
          "action" => "approve"
        })

      # Should redirect with error
      redirect_url = redirected_to(conn)
      assert redirect_url =~ "https://example.com/callback"
      assert redirect_url =~ "error=invalid_request"
      assert redirect_url =~ URI.encode_www_form("At least one permission must be selected")

      # Verify no authorization code was created
      auth_code = Repo.get_by(Hexpm.OAuth.AuthorizationCode, client_id: client.client_id)
      refute auth_code
    end

    test "approves with selected scopes only", %{client: client, user: user} do
      conn = login_user(build_conn(), user)

      conn =
        post(conn, ~p"/oauth/authorize", %{
          "client_id" => client.client_id,
          "redirect_uri" => "https://example.com/callback",
          "scope" => "api:read api:write repositories",
          "code_challenge" => "challenge123",
          "code_challenge_method" => "S256",
          "action" => "approve",
          "selected_scopes" => ["api:read", "repositories"]
        })

      # Should redirect with authorization code
      assert redirected_to(conn) =~ "https://example.com/callback?code="

      # Verify authorization code was created with only selected scopes
      auth_code = Repo.get_by(Hexpm.OAuth.AuthorizationCode, client_id: client.client_id)
      assert auth_code
      assert auth_code.scopes == ["api:read", "repositories"]
    end

    test "denies authorization", %{client: client, user: user} do
      conn = login_user(build_conn(), user)

      conn =
        post(conn, ~p"/oauth/authorize", %{
          "client_id" => client.client_id,
          "redirect_uri" => "https://example.com/callback",
          "scope" => "api:read",
          "code_challenge" => "challenge123",
          "code_challenge_method" => "S256",
          "action" => "deny"
        })

      # Should redirect with error
      redirect_url = redirected_to(conn)
      assert redirect_url =~ "https://example.com/callback"
      assert redirect_url =~ "error=access_denied"

      # Verify no authorization code was created
      auth_code = Repo.get_by(Hexpm.OAuth.AuthorizationCode, client_id: client.client_id)
      refute auth_code
    end

    test "returns error when no scopes are selected", %{client: client, user: user} do
      conn = login_user(build_conn(), user)

      conn =
        post(conn, ~p"/oauth/authorize", %{
          "client_id" => client.client_id,
          "redirect_uri" => "https://example.com/callback",
          "scope" => "api:read repositories",
          "code_challenge" => "challenge123",
          "code_challenge_method" => "S256",
          "action" => "approve",
          "selected_scopes" => []
        })

      # Should redirect with error
      redirect_url = redirected_to(conn)
      assert redirect_url =~ "https://example.com/callback"
      assert redirect_url =~ "error=invalid_request"
      assert redirect_url =~ URI.encode_www_form("At least one permission must be selected")

      # Verify no authorization code was created
      auth_code = Repo.get_by(Hexpm.OAuth.AuthorizationCode, client_id: client.client_id)
      refute auth_code
    end

    test "returns error when invalid scopes are selected", %{client: client, user: user} do
      conn = login_user(build_conn(), user)

      conn =
        post(conn, ~p"/oauth/authorize", %{
          "client_id" => client.client_id,
          "redirect_uri" => "https://example.com/callback",
          "scope" => "api:read",
          "code_challenge" => "challenge123",
          "code_challenge_method" => "S256",
          "action" => "approve",
          # Not in the original request
          "selected_scopes" => ["api:write"]
        })

      # Should redirect with error
      redirect_url = redirected_to(conn)
      assert redirect_url =~ "https://example.com/callback"
      assert redirect_url =~ "error=invalid_request"
      assert redirect_url =~ URI.encode_www_form("Invalid scopes selected")

      # Verify no authorization code was created
      auth_code = Repo.get_by(Hexpm.OAuth.AuthorizationCode, client_id: client.client_id)
      refute auth_code
    end

    test "returns error for missing PKCE parameters", %{client: client, user: user} do
      conn = login_user(build_conn(), user)

      conn =
        post(conn, ~p"/oauth/authorize", %{
          "client_id" => client.client_id,
          "redirect_uri" => "https://example.com/callback",
          "scope" => "api:read",
          "action" => "approve",
          "selected_scopes" => ["api:read"]
        })

      # Should redirect with error
      redirect_url = redirected_to(conn)
      assert redirect_url =~ "https://example.com/callback"
      assert redirect_url =~ "error=invalid_request"
      assert redirect_url =~ "code_challenge"
    end
  end
end
