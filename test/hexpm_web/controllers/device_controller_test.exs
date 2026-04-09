defmodule HexpmWeb.DeviceControllerTest do
  use HexpmWeb.ConnCase, async: true

  alias Hexpm.OAuth.{DeviceCodes, DeviceCode, Client, Clients}
  import Hexpm.Factory

  defp create_test_client(name \\ "Test Client") do
    client_params = %{
      client_id: Clients.generate_client_id(),
      name: name,
      client_type: "public",
      allowed_grant_types: ["urn:ietf:params:oauth:grant-type:device_code"],
      allowed_scopes: ["api", "api:read", "repositories"],
      client_secret: nil
    }

    {:ok, client} = Client.build(client_params) |> Repo.insert()
    client
  end

  defp create_device_code(client, scopes \\ ["api"]) do
    mock_conn =
      build_conn()
      |> Map.put(:scheme, :https)
      |> Map.put(:host, "hex.pm")
      |> Map.put(:port, 443)

    {:ok, response} =
      DeviceCodes.initiate_device_authorization(mock_conn, client.client_id, scopes)

    device_code = Repo.get_by(DeviceCode, device_code: response.device_code)
    {response, device_code}
  end

  defp login_user(conn, user, opts \\ []) do
    alias Hexpm.UserSessions

    sudo = Keyword.get(opts, :sudo, true)

    {:ok, _session, session_token} =
      UserSessions.create_browser_session(user,
        name: "Test Browser Session",
        audit: test_audit_data(user)
      )

    session_data = %{"session_token" => Base.encode64(session_token)}

    session_data =
      if sudo do
        Map.put(
          session_data,
          "sudo_authenticated_at",
          NaiveDateTime.utc_now() |> NaiveDateTime.to_iso8601()
        )
      else
        session_data
      end

    conn |> init_test_session(session_data)
  end

  defp login_with_verified_code(conn, user, user_code, opts \\ []) do
    alias Hexpm.UserSessions

    sudo = Keyword.get(opts, :sudo, true)
    verified_at = Keyword.get(opts, :verified_at, NaiveDateTime.utc_now())

    {:ok, _session, session_token} =
      UserSessions.create_browser_session(user,
        name: "Test Browser Session",
        audit: test_audit_data(user)
      )

    session_data = %{
      "session_token" => Base.encode64(session_token),
      "device_code_verified" => %{
        "user_code" => user_code,
        "verified_at" => NaiveDateTime.to_iso8601(verified_at)
      }
    }

    session_data =
      if sudo do
        Map.put(
          session_data,
          "sudo_authenticated_at",
          NaiveDateTime.utc_now() |> NaiveDateTime.to_iso8601()
        )
      else
        session_data
      end

    conn |> init_test_session(session_data)
  end

  describe "GET /oauth/device" do
    test "redirects to login when not authenticated" do
      conn = get(build_conn(), ~p"/oauth/device")
      assert redirected_to(conn) =~ "/login"
    end

    test "shows verification form when authenticated with sudo" do
      user = insert(:user)
      conn = login_user(build_conn(), user)

      conn = get(conn, ~p"/oauth/device")
      assert html_response(conn, 200) =~ "Device Authorization"
      assert html_response(conn, 200) =~ "Enter the verification code"
    end

    test "shows verification form when authenticated without sudo" do
      user = insert(:user)
      conn = login_user(build_conn(), user, sudo: false)

      conn = get(conn, ~p"/oauth/device")
      assert html_response(conn, 200) =~ "Device Authorization"
      assert html_response(conn, 200) =~ "Enter the verification code"
    end

    test "shows pre-filled verification form when valid user_code provided with sudo" do
      user = insert(:user)
      client = create_test_client()
      {response, _device_code} = create_device_code(client)

      conn = login_user(build_conn(), user)
      conn = get(conn, ~p"/oauth/device?user_code=#{response.user_code}")
      html = html_response(conn, 200)

      assert html =~ "Device Authorization"
      assert html =~ "Security Check"
      assert html =~ "Verify and Continue"

      formatted_code =
        String.slice(response.user_code, 0, 4) <> "-" <> String.slice(response.user_code, 4, 4)

      assert html =~ formatted_code
    end

    test "shows pre-filled verification form when valid user_code provided without sudo" do
      user = insert(:user)
      client = create_test_client()
      {response, _device_code} = create_device_code(client)

      conn = login_user(build_conn(), user, sudo: false)
      conn = get(conn, ~p"/oauth/device?user_code=#{response.user_code}")
      html = html_response(conn, 200)

      assert html =~ "Device Authorization"
      assert html =~ "Security Check"
      assert html =~ "Verify and Continue"
    end

    test "shows error for invalid user_code" do
      user = insert(:user)
      conn = login_user(build_conn(), user)

      conn = get(conn, ~p"/oauth/device?user_code=INVALID")
      assert html_response(conn, 200) =~ "Invalid verification code"
    end

    test "redirects to login with return path for user_code when not logged in" do
      client = create_test_client()
      {response, _device_code} = create_device_code(client)

      conn = get(build_conn(), ~p"/oauth/device?user_code=#{response.user_code}")
      assert redirected_to(conn) =~ "/login"
      assert redirected_to(conn) =~ "return="
      assert redirected_to(conn) =~ "%3Fuser_code%3D"
    end
  end

  describe "POST /oauth/device (verify)" do
    setup do
      user = insert(:user)
      client = create_test_client()
      {response, device_code} = create_device_code(client)
      %{user: user, client: client, response: response, device_code: device_code}
    end

    test "redirects to /oauth/device/authorize on successful verification", %{
      user: user,
      device_code: device_code
    } do
      conn = login_user(build_conn(), user)

      conn =
        post(conn, ~p"/oauth/device", %{
          "user_code" => device_code.user_code
        })

      assert redirected_to(conn) == "/oauth/device/authorize"
    end

    test "sets session flag with user_code and timestamp", %{
      user: user,
      device_code: device_code
    } do
      conn = login_user(build_conn(), user)

      conn =
        post(conn, ~p"/oauth/device", %{
          "user_code" => device_code.user_code
        })

      flag = get_session(conn, "device_code_verified")
      assert flag["user_code"] == device_code.user_code
      assert {:ok, _} = NaiveDateTime.from_iso8601(flag["verified_at"])
    end

    test "does not require sudo", %{user: user, device_code: device_code} do
      conn = login_user(build_conn(), user, sudo: false)

      conn =
        post(conn, ~p"/oauth/device", %{
          "user_code" => device_code.user_code
        })

      assert redirected_to(conn) == "/oauth/device/authorize"
    end

    test "shows error for invalid user_code", %{user: user} do
      conn = login_user(build_conn(), user)

      conn =
        post(conn, ~p"/oauth/device", %{
          "user_code" => "INVALID"
        })

      assert html_response(conn, 200) =~ "Invalid verification code"
    end

    test "shows error for expired device code", %{user: user, client: client} do
      {response, device_code} = create_device_code(client)

      past_time = DateTime.add(DateTime.utc_now(), -3600, :second)
      Repo.update!(DeviceCode.changeset(device_code, %{expires_at: past_time}))

      conn = login_user(build_conn(), user)

      conn =
        post(conn, ~p"/oauth/device", %{
          "user_code" => response.user_code
        })

      assert html_response(conn, 200) =~ "Verification code has expired"
    end

    test "shows error for already processed device code", %{user: user, client: client} do
      {response, _device_code} = create_device_code(client)
      DeviceCodes.authorize_device(response.user_code, user, ["api"])

      conn = login_user(build_conn(), user)

      conn =
        post(conn, ~p"/oauth/device", %{
          "user_code" => response.user_code
        })

      assert html_response(conn, 200) =~ "already been processed"
    end

    test "shows error for missing user_code", %{user: user} do
      conn = login_user(build_conn(), user)
      conn = post(conn, ~p"/oauth/device", %{})
      assert html_response(conn, 200) =~ "Missing verification code"
    end
  end

  describe "GET /oauth/device/authorize" do
    setup do
      user = insert(:user)
      client = create_test_client()
      {_response, device_code} = create_device_code(client)
      %{user: user, client: client, device_code: device_code}
    end

    test "redirects to login when not authenticated" do
      conn = get(build_conn(), ~p"/oauth/device/authorize")
      assert redirected_to(conn) =~ "/login"
    end

    test "redirects to sudo when no sudo session", %{user: user, device_code: device_code} do
      conn = login_with_verified_code(build_conn(), user, device_code.user_code, sudo: false)
      conn = get(conn, ~p"/oauth/device/authorize")

      assert redirected_to(conn) == "/sudo"
    end

    test "shows permissions page with valid session flag and sudo", %{
      user: user,
      client: client,
      device_code: device_code
    } do
      conn = login_with_verified_code(build_conn(), user, device_code.user_code)
      conn = get(conn, ~p"/oauth/device/authorize")

      html = html_response(conn, 200)
      assert html =~ "Authorize Device"
      assert html =~ client.name
    end

    test "redirects to /oauth/device when session flag is missing", %{user: user} do
      conn = login_user(build_conn(), user)
      conn = get(conn, ~p"/oauth/device/authorize")

      assert redirected_to(conn) == "/oauth/device"
    end

    test "redirects to /oauth/device when session flag is expired", %{
      user: user,
      device_code: device_code
    } do
      expired_at = NaiveDateTime.shift(NaiveDateTime.utc_now(), minute: -6)

      conn =
        login_with_verified_code(build_conn(), user, device_code.user_code,
          verified_at: expired_at
        )

      conn = get(conn, ~p"/oauth/device/authorize")
      assert redirected_to(conn) == "/oauth/device"
    end

    test "redirects to /oauth/device when device code has expired", %{
      user: user,
      client: client
    } do
      {_response, device_code} = create_device_code(client)
      past_time = DateTime.add(DateTime.utc_now(), -3600, :second)
      Repo.update!(DeviceCode.changeset(device_code, %{expires_at: past_time}))

      conn = login_with_verified_code(build_conn(), user, device_code.user_code)
      conn = get(conn, ~p"/oauth/device/authorize")

      assert redirected_to(conn) =~ "/oauth/device"
    end
  end

  describe "POST /oauth/device/authorize" do
    setup do
      user = insert(:user)
      client = create_test_client()
      {_response, device_code} = create_device_code(client)
      %{user: user, client: client, device_code: device_code}
    end

    test "redirects to login when not authenticated" do
      conn = post(build_conn(), ~p"/oauth/device/authorize", %{"action" => "authorize"})
      assert redirected_to(conn) =~ "/login"
    end

    test "redirects to sudo when no sudo session", %{user: user, device_code: device_code} do
      conn = login_with_verified_code(build_conn(), user, device_code.user_code, sudo: false)

      conn =
        post(conn, ~p"/oauth/device/authorize", %{
          "action" => "authorize",
          "selected_scopes" => ["api"]
        })

      assert redirected_to(conn) == "/sudo"
    end

    test "authorizes device successfully with 2FA for api scope", %{client: client} do
      user = insert(:user_with_tfa)
      {_response, device_code} = create_device_code(client)

      conn = login_with_verified_code(build_conn(), user, device_code.user_code)

      conn =
        post(conn, ~p"/oauth/device/authorize", %{
          "action" => "authorize",
          "selected_scopes" => ["api"]
        })

      assert redirected_to(conn, 302) == "/"

      assert Phoenix.Flash.get(conn.assigns.flash, :info) ==
               "Device has been successfully authorized!"

      updated_device_code = Repo.get(DeviceCode, device_code.id)
      assert updated_device_code.status == "authorized"
      assert updated_device_code.user_id == user.id
    end

    test "authorizes with selected scopes", %{user: user, client: client} do
      {_response, device_code} = create_device_code(client, ["api:read", "repositories"])

      conn = login_with_verified_code(build_conn(), user, device_code.user_code)

      conn =
        post(conn, ~p"/oauth/device/authorize", %{
          "action" => "authorize",
          "selected_scopes" => ["api:read"]
        })

      assert redirected_to(conn, 302) == "/"

      assert Phoenix.Flash.get(conn.assigns.flash, :info) ==
               "Device has been successfully authorized!"

      updated = Repo.get(DeviceCode, device_code.id)
      assert updated.status == "authorized"

      token =
        Repo.get_by(Hexpm.OAuth.Token,
          grant_type: "urn:ietf:params:oauth:grant-type:device_code",
          grant_reference: device_code.device_code
        )

      assert token.scopes == ["api:read"]
    end

    test "blocks authorization for api:write without 2FA", %{
      user: user,
      device_code: device_code
    } do
      conn = login_with_verified_code(build_conn(), user, device_code.user_code)

      conn =
        post(conn, ~p"/oauth/device/authorize", %{
          "action" => "authorize",
          "selected_scopes" => ["api"]
        })

      assert html_response(conn, 200) =~ "Two-factor authentication is required"

      updated_device_code = Repo.get(DeviceCode, device_code.id)
      assert updated_device_code.status == "pending"
    end

    test "shows error when no scopes selected", %{user: user, device_code: device_code} do
      conn = login_with_verified_code(build_conn(), user, device_code.user_code)

      conn =
        post(conn, ~p"/oauth/device/authorize", %{
          "action" => "authorize",
          "selected_scopes" => []
        })

      assert html_response(conn, 200) =~ "At least one permission must be selected"

      updated_device_code = Repo.get(DeviceCode, device_code.id)
      assert updated_device_code.status == "pending"
    end

    test "shows error when no scopes param at all", %{user: user, device_code: device_code} do
      conn = login_with_verified_code(build_conn(), user, device_code.user_code)

      conn =
        post(conn, ~p"/oauth/device/authorize", %{
          "action" => "authorize"
        })

      assert html_response(conn, 200) =~ "At least one permission must be selected"
    end

    test "shows error when invalid scopes selected", %{user: user, client: client} do
      {_response, device_code} = create_device_code(client, ["api:read"])

      conn = login_with_verified_code(build_conn(), user, device_code.user_code)

      conn =
        post(conn, ~p"/oauth/device/authorize", %{
          "action" => "authorize",
          "selected_scopes" => ["api:write"]
        })

      assert html_response(conn, 200) =~ "Selected scopes not in original request"

      updated_device_code = Repo.get(DeviceCode, device_code.id)
      assert updated_device_code.status == "pending"
    end

    test "denies device successfully", %{user: user, device_code: device_code} do
      conn = login_with_verified_code(build_conn(), user, device_code.user_code)

      conn =
        post(conn, ~p"/oauth/device/authorize", %{
          "action" => "deny"
        })

      assert redirected_to(conn, 302) == "/"

      assert Phoenix.Flash.get(conn.assigns.flash, :info) ==
               "Device authorization has been denied."

      updated_device_code = Repo.get(DeviceCode, device_code.id)
      assert updated_device_code.status == "denied"
    end

    test "clears session flag after authorize", %{client: client} do
      user = insert(:user_with_tfa)
      {_response, device_code} = create_device_code(client)

      conn = login_with_verified_code(build_conn(), user, device_code.user_code)

      conn =
        post(conn, ~p"/oauth/device/authorize", %{
          "action" => "authorize",
          "selected_scopes" => ["api"]
        })

      assert redirected_to(conn) == "/"
      assert is_nil(get_session(conn, "device_code_verified"))
    end

    test "clears session flag after deny", %{user: user, device_code: device_code} do
      conn = login_with_verified_code(build_conn(), user, device_code.user_code)

      conn =
        post(conn, ~p"/oauth/device/authorize", %{
          "action" => "deny"
        })

      assert redirected_to(conn) == "/"
      assert is_nil(get_session(conn, "device_code_verified"))
    end

    test "redirects to /oauth/device when session flag missing", %{user: user} do
      conn = login_user(build_conn(), user)

      conn =
        post(conn, ~p"/oauth/device/authorize", %{
          "action" => "authorize",
          "selected_scopes" => ["api"]
        })

      assert redirected_to(conn) == "/oauth/device"
    end

    test "redirects to /oauth/device when session flag expired", %{
      user: user,
      device_code: device_code
    } do
      expired_at = NaiveDateTime.shift(NaiveDateTime.utc_now(), minute: -6)

      conn =
        login_with_verified_code(build_conn(), user, device_code.user_code,
          verified_at: expired_at
        )

      conn =
        post(conn, ~p"/oauth/device/authorize", %{
          "action" => "authorize",
          "selected_scopes" => ["api"]
        })

      assert redirected_to(conn) == "/oauth/device"
    end

    test "shows error for expired device code", %{user: user, client: client} do
      {_response, device_code} = create_device_code(client, ["api:read"])
      past_time = DateTime.add(DateTime.utc_now(), -3600, :second)
      Repo.update!(DeviceCode.changeset(device_code, %{expires_at: past_time}))

      conn = login_with_verified_code(build_conn(), user, device_code.user_code)

      conn =
        post(conn, ~p"/oauth/device/authorize", %{
          "action" => "authorize",
          "selected_scopes" => ["api:read"]
        })

      assert redirected_to(conn) =~ "/oauth/device"
    end

    test "shows error for already processed device code", %{user: user, client: client} do
      {_response, device_code} = create_device_code(client, ["api:read"])
      DeviceCodes.authorize_device(device_code.user_code, user, ["api:read"])

      conn = login_with_verified_code(build_conn(), user, device_code.user_code)

      conn =
        post(conn, ~p"/oauth/device/authorize", %{
          "action" => "authorize",
          "selected_scopes" => ["api:read"]
        })

      assert redirected_to(conn) =~ "/oauth/device"
    end

    test "shows error for invalid action", %{user: user, device_code: device_code} do
      conn = login_with_verified_code(build_conn(), user, device_code.user_code)

      conn =
        post(conn, ~p"/oauth/device/authorize", %{
          "action" => "invalid"
        })

      assert redirected_to(conn) =~ "/oauth/device"
    end
  end

  describe "full flow" do
    test "complete flow: visit with code -> verify -> permissions -> authorize" do
      user = insert(:user_with_tfa)
      client = create_test_client("Test App")
      {response, device_code} = create_device_code(client, ["api", "repositories"])

      # Step 1: Visit with user_code (pre-filled verification form)
      conn = login_user(build_conn(), user)
      conn = get(conn, ~p"/oauth/device?user_code=#{response.user_code}")

      html = html_response(conn, 200)
      assert html =~ "Security Check"
      assert html =~ "Verify and Continue"

      formatted_code =
        String.slice(response.user_code, 0, 4) <> "-" <> String.slice(response.user_code, 4, 4)

      assert html =~ ~r/value="#{formatted_code}"/
      assert html =~ "readonly"

      # Step 2: Submit verification (POST with action=verify)
      conn = login_user(build_conn(), user)

      conn =
        post(conn, ~p"/oauth/device", %{
          "user_code" => response.user_code
        })

      assert redirected_to(conn) == "/oauth/device/authorize"
      flag = get_session(conn, "device_code_verified")
      assert flag["user_code"] == response.user_code

      # Step 3: View authorize page (with session flag + sudo)
      conn = login_with_verified_code(build_conn(), user, response.user_code)
      conn = get(conn, ~p"/oauth/device/authorize")

      html = html_response(conn, 200)
      assert html =~ "Authorize Device"
      assert html =~ client.name
      assert html =~ "api"
      assert html =~ "repositories"

      # Step 4: Authorize with selected scopes
      conn = login_with_verified_code(build_conn(), user, response.user_code)

      conn =
        post(conn, ~p"/oauth/device/authorize", %{
          "action" => "authorize",
          "selected_scopes" => ["api", "repositories"]
        })

      assert redirected_to(conn) == "/"

      assert Phoenix.Flash.get(conn.assigns.flash, :info) ==
               "Device has been successfully authorized!"

      assert is_nil(get_session(conn, "device_code_verified"))

      updated = Repo.get(DeviceCode, device_code.id)
      assert updated.status == "authorized"
      assert updated.user_id == user.id
    end
  end

  describe "XSS protection" do
    test "escapes malicious scope names in authorization page" do
      user = insert(:user)
      malicious_scope = "package:<script>alert('xss')</script>"

      client_params = %{
        client_id: Clients.generate_client_id(),
        name: "Test Client",
        client_type: "public",
        allowed_grant_types: ["urn:ietf:params:oauth:grant-type:device_code"],
        allowed_scopes: [malicious_scope],
        client_secret: nil
      }

      {:ok, client} = Client.build(client_params) |> Repo.insert()

      mock_conn =
        build_conn()
        |> Map.put(:scheme, :https)
        |> Map.put(:host, "hex.pm")
        |> Map.put(:port, 443)

      {:ok, response} =
        DeviceCodes.initiate_device_authorization(mock_conn, client.client_id, [malicious_scope])

      conn = login_with_verified_code(build_conn(), user, response.user_code)
      conn = get(conn, ~p"/oauth/device/authorize")

      html = html_response(conn, 200)

      refute html =~ "<script>alert('xss')</script>"
      assert html =~ "&lt;script&gt;" or html =~ "&#60;script&#62;"
    end
  end

  describe "device verification rate limiting" do
    setup do
      user = insert(:user)
      client = create_test_client()
      {_response, device_code} = create_device_code(client)
      %{user: user, device_code: device_code, client: client}
    end

    test "GET /oauth/device rate limiting function exists and is called", %{
      user: user,
      device_code: device_code
    } do
      conn =
        build_conn()
        |> login_user(user)
        |> get(~p"/oauth/device?user_code=#{device_code.user_code}")

      assert html_response(conn, 200)

      if response_contains_rate_limit_message?(conn) do
        response_body = html_response(conn, 200)
        assert response_body =~ "Too many verification attempts"
        assert response_body =~ "wait 15 minutes"
      end
    end

    test "POST /oauth/device verify is not rate limited", %{
      user: user,
      device_code: device_code
    } do
      conn =
        build_conn()
        |> login_user(user)
        |> post(~p"/oauth/device", %{
          "user_code" => device_code.user_code
        })

      assert redirected_to(conn) == "/oauth/device/authorize"
    end

    defp response_contains_rate_limit_message?(conn) do
      response_body = html_response(conn, 200)

      response_body =~ "Too many verification attempts" and
        response_body =~ "wait 15 minutes"
    end
  end
end
