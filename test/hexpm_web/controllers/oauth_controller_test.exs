defmodule HexpmWeb.OAuthControllerTest do
  use HexpmWeb.ConnCase, async: true

  alias Hexpm.OAuth.{Client, Clients}
  import Hexpm.Factory

  defp login_user(conn, user) do
    alias Hexpm.UserSessions

    {:ok, _session, session_token} =
      UserSessions.create_browser_session(user,
        name: "Test Browser Session",
        audit: test_audit_data(user)
      )

    conn
    |> init_test_session(%{})
    |> put_session("session_token", Base.encode64(session_token))
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

  defp create_hexdocs_client do
    client_params = %{
      client_id: Clients.generate_client_id(),
      name: "Hexdocs",
      client_type: "confidential",
      allowed_grant_types: ["authorization_code", "refresh_token"],
      allowed_scopes: ["docs"],
      redirect_uris: ["https://*.hexdocs.pm/oauth/callback"],
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
          "state" => "test_state",
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
          "state" => "test_state",
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
          "state" => "test_state",
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
          "state" => "test_state",
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
          "state" => "test_state",
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
          "state" => "test_state",
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
          "state" => "test_state",
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
          "state" => "test_state",
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

  describe "hexdocs OAuth flow (docs scope with wildcard redirect)" do
    setup do
      client = create_hexdocs_client()
      user = insert(:user)
      organization = insert(:organization)
      insert(:organization_user, organization: organization, user: user)
      %{client: client, user: user, organization: organization}
    end

    test "accepts docs:{org} scope with wildcard redirect URI", %{
      client: client,
      user: user,
      organization: organization
    } do
      conn = login_user(build_conn(), user)

      # Hexdocs would redirect to this URL with the organization subdomain
      redirect_uri = "https://#{organization.name}.hexdocs.pm/oauth/callback"

      conn =
        post(conn, ~p"/oauth/authorize", %{
          "client_id" => client.client_id,
          "redirect_uri" => redirect_uri,
          "scope" => "docs:#{organization.name}",
          "state" => "test_state",
          "code_challenge" => "challenge123",
          "code_challenge_method" => "S256",
          "action" => "approve",
          "selected_scopes" => ["docs:#{organization.name}"]
        })

      # Should redirect with authorization code
      redirect_url = redirected_to(conn)
      assert redirect_url =~ redirect_uri
      assert redirect_url =~ "code="

      # Verify authorization code was created with docs scope
      auth_code = Repo.get_by(Hexpm.OAuth.AuthorizationCode, client_id: client.client_id)
      assert auth_code
      assert auth_code.scopes == ["docs:#{organization.name}"]
    end

    test "rejects redirect URI that doesn't match wildcard pattern", %{
      client: client,
      user: user,
      organization: organization
    } do
      conn = login_user(build_conn(), user)

      # Try to use a redirect URI that doesn't match the wildcard
      conn =
        get(conn, ~p"/oauth/authorize", %{
          "client_id" => client.client_id,
          "redirect_uri" => "https://evil.com/oauth/callback",
          "scope" => "docs:#{organization.name}",
          "state" => "test_state",
          "code_challenge" => "challenge123",
          "code_challenge_method" => "S256"
        })

      # Should show error (not redirect to evil.com)
      response = json_response(conn, 400)
      assert response["error"] == "invalid_request"
      assert response["error_description"] =~ "Invalid redirect_uri"
    end

    test "rejects multi-level subdomain that doesn't match wildcard", %{
      client: client,
      user: user,
      organization: organization
    } do
      conn = login_user(build_conn(), user)

      # Wildcard should only match single subdomain segment
      conn =
        get(conn, ~p"/oauth/authorize", %{
          "client_id" => client.client_id,
          "redirect_uri" => "https://evil.#{organization.name}.hexdocs.pm/oauth/callback",
          "scope" => "docs:#{organization.name}",
          "state" => "test_state",
          "code_challenge" => "challenge123",
          "code_challenge_method" => "S256"
        })

      response = json_response(conn, 400)
      assert response["error"] == "invalid_request"
      assert response["error_description"] =~ "Invalid redirect_uri"
    end

    test "rejects docs scope for organization user doesn't have access to", %{
      client: client,
      user: user
    } do
      other_org = insert(:organization)
      conn = login_user(build_conn(), user)

      conn =
        post(conn, ~p"/oauth/authorize", %{
          "client_id" => client.client_id,
          "redirect_uri" => "https://#{other_org.name}.hexdocs.pm/oauth/callback",
          "scope" => "docs:#{other_org.name}",
          "state" => "test_state",
          "code_challenge" => "challenge123",
          "code_challenge_method" => "S256",
          "action" => "approve",
          "selected_scopes" => ["docs:#{other_org.name}"]
        })

      # Should redirect with error - user doesn't have access to this org
      redirect_url = redirected_to(conn)
      assert redirect_url =~ "error="
    end
  end
end
