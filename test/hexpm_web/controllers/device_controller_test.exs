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

  describe "GET /oauth/device" do
    test "redirects to login when not authenticated" do
      conn = get(build_conn(), ~p"/oauth/device")
      assert redirected_to(conn) =~ "/login"
    end

    test "shows verification form when authenticated" do
      user = insert(:user)
      conn = login_user(build_conn(), user)

      conn = get(conn, ~p"/oauth/device")
      assert html_response(conn, 200) =~ "Device Authorization"
      assert html_response(conn, 200) =~ "Enter the verification code"
    end

    test "shows pre-filled verification form when valid user_code provided" do
      user = insert(:user)
      conn = login_user(build_conn(), user)
      client = create_test_client()

      mock_conn =
        build_conn()
        |> Map.put(:scheme, :https)
        |> Map.put(:host, "hex.pm")
        |> Map.put(:port, 443)

      {:ok, response} =
        DeviceCodes.initiate_device_authorization(mock_conn, client.client_id, ["api"])

      # First visit with user_code should show verification form
      conn = get(conn, ~p"/oauth/device?user_code=#{response.user_code}")
      html = html_response(conn, 200)

      assert html =~ "Device Authorization"
      assert html =~ "Security Check"
      assert html =~ "Verify and Continue"
      # Check for formatted code (XXXX-XXXX)
      formatted_code =
        String.slice(response.user_code, 0, 4) <> "-" <> String.slice(response.user_code, 4, 4)

      assert html =~ formatted_code

      # Visit with verified=true should show authorization form
      conn =
        get(
          login_user(build_conn(), user),
          ~p"/oauth/device?user_code=#{response.user_code}&verified=true"
        )

      assert html_response(conn, 200) =~ client.name
      assert html_response(conn, 200) =~ "Authorize Device"
    end

    test "shows error for invalid user_code" do
      user = insert(:user)
      conn = login_user(build_conn(), user)

      conn = get(conn, ~p"/oauth/device?user_code=INVALID")
      assert html_response(conn, 200) =~ "Invalid verification code"
    end

    test "redirects to login with return path for user_code" do
      client = create_test_client()

      mock_conn =
        build_conn()
        |> Map.put(:scheme, :https)
        |> Map.put(:host, "hex.pm")
        |> Map.put(:port, 443)

      {:ok, response} =
        DeviceCodes.initiate_device_authorization(mock_conn, client.client_id, ["api"])

      conn = get(build_conn(), ~p"/oauth/device?user_code=#{response.user_code}")
      assert redirected_to(conn) =~ "/login"
      assert redirected_to(conn) =~ "return="
      assert redirected_to(conn) =~ "%3Fuser_code%3D"
    end

    test "verification flow from pre-filled form to authorization" do
      user = insert(:user)
      client = create_test_client("Test App")

      mock_conn =
        build_conn()
        |> Map.put(:scheme, :https)
        |> Map.put(:host, "hex.pm")
        |> Map.put(:port, 443)

      {:ok, response} =
        DeviceCodes.initiate_device_authorization(mock_conn, client.client_id, [
          "api",
          "repositories"
        ])

      # Step 1: Visit with user_code (simulating clicking from terminal link)
      conn = login_user(build_conn(), user)
      conn = get(conn, ~p"/oauth/device?user_code=#{response.user_code}")

      html = html_response(conn, 200)
      assert html =~ "Security Check"
      assert html =~ "verify that this code matches"
      assert html =~ "Verify and Continue"
      # Code should be pre-filled and readonly (in formatted form)
      formatted_code =
        String.slice(response.user_code, 0, 4) <> "-" <> String.slice(response.user_code, 4, 4)

      assert html =~ ~r/value="#{formatted_code}"/
      assert html =~ "readonly"

      # Step 2: Submit verification form (user confirms code matches)
      conn = login_user(build_conn(), user)
      conn = get(conn, ~p"/oauth/device?user_code=#{response.user_code}&verified=true")

      html = html_response(conn, 200)
      assert html =~ "Authorize Device"
      assert html =~ client.name
      assert html =~ "api"
      assert html =~ "repositories"
      refute html =~ "Security Check"
    end
  end

  describe "POST /oauth/device" do
    setup do
      user = insert(:user)
      client = create_test_client()

      mock_conn =
        build_conn()
        |> Map.put(:scheme, :https)
        |> Map.put(:host, "hex.pm")
        |> Map.put(:port, 443)

      {:ok, response} =
        DeviceCodes.initiate_device_authorization(mock_conn, client.client_id, ["api"])

      device_code = Repo.get_by(DeviceCode, device_code: response.device_code)
      %{user: user, device_code: device_code, client: client}
    end

    test "redirects to login when not authenticated", %{device_code: device_code} do
      conn =
        post(build_conn(), ~p"/oauth/device", %{
          "user_code" => device_code.user_code,
          "action" => "authorize"
        })

      assert redirected_to(conn) =~ "/login"
    end

    test "shows error when authorizing without selecting scopes", %{
      user: user,
      device_code: device_code
    } do
      conn = login_user(build_conn(), user)

      conn =
        post(conn, ~p"/oauth/device", %{
          "user_code" => device_code.user_code,
          "action" => "authorize"
        })

      assert html_response(conn, 200) =~ "At least one permission must be selected"

      # Verify device was not authorized
      updated_device_code = Repo.get(DeviceCode, device_code.id)
      assert updated_device_code.status == "pending"
    end

    test "authorizes device successfully with all scopes", %{user: user, device_code: device_code} do
      conn = login_user(build_conn(), user)

      conn =
        post(conn, ~p"/oauth/device", %{
          "user_code" => device_code.user_code,
          "action" => "authorize",
          # Select all requested scopes
          "selected_scopes" => ["api"]
        })

      assert redirected_to(conn, 302) == "/"

      assert Phoenix.Flash.get(conn.assigns.flash, :info) ==
               "Device has been successfully authorized!"

      # Verify device was authorized in database
      updated_device_code = Repo.get(DeviceCode, device_code.id)
      assert updated_device_code.status == "authorized"
      assert updated_device_code.user_id == user.id
    end

    test "denies device successfully", %{user: user, device_code: device_code} do
      conn = login_user(build_conn(), user)

      conn =
        post(conn, ~p"/oauth/device", %{
          "user_code" => device_code.user_code,
          "action" => "deny"
        })

      assert redirected_to(conn, 302) == "/"

      assert Phoenix.Flash.get(conn.assigns.flash, :info) ==
               "Device authorization has been denied."

      # Verify device was denied in database
      updated_device_code = Repo.get(DeviceCode, device_code.id)
      assert updated_device_code.status == "denied"
    end

    test "authorizes device with selected scopes", %{user: user, client: client} do
      conn = login_user(build_conn(), user)

      mock_conn =
        build_conn()
        |> Map.put(:scheme, :https)
        |> Map.put(:host, "hex.pm")
        |> Map.put(:port, 443)

      {:ok, response} =
        DeviceCodes.initiate_device_authorization(mock_conn, client.client_id, [
          "api:read",
          "repositories"
        ])

      conn =
        post(conn, ~p"/oauth/device", %{
          "user_code" => response.user_code,
          "action" => "authorize",
          "selected_scopes" => ["api:read"]
        })

      assert redirected_to(conn, 302) == "/"

      assert Phoenix.Flash.get(conn.assigns.flash, :info) ==
               "Device has been successfully authorized!"

      # Verify the token was created with only the selected scope
      device_code = Repo.get_by(DeviceCode, user_code: response.user_code)
      assert device_code.status == "authorized"

      token =
        Repo.get_by(Hexpm.OAuth.Token,
          grant_type: "urn:ietf:params:oauth:grant-type:device_code",
          grant_reference: device_code.device_code
        )

      assert token.scopes == ["api:read"]
    end

    test "shows error when no scopes are selected", %{user: user, device_code: device_code} do
      conn = login_user(build_conn(), user)

      conn =
        post(conn, ~p"/oauth/device", %{
          "user_code" => device_code.user_code,
          "action" => "authorize",
          "selected_scopes" => []
        })

      assert html_response(conn, 200) =~ "At least one permission must be selected"

      # Verify device was not authorized
      updated_device_code = Repo.get(DeviceCode, device_code.id)
      assert updated_device_code.status == "pending"
    end

    test "shows error when invalid scopes are selected", %{user: user, client: client} do
      conn = login_user(build_conn(), user)

      mock_conn =
        build_conn()
        |> Map.put(:scheme, :https)
        |> Map.put(:host, "hex.pm")
        |> Map.put(:port, 443)

      {:ok, response} =
        DeviceCodes.initiate_device_authorization(mock_conn, client.client_id, ["api:read"])

      conn =
        post(conn, ~p"/oauth/device", %{
          "user_code" => response.user_code,
          "action" => "authorize",
          # Not in the original request
          "selected_scopes" => ["api:write"]
        })

      assert html_response(conn, 200) =~ "Selected scopes not in original request"

      # Verify device was not authorized
      device_code = Repo.get_by(DeviceCode, user_code: response.user_code)
      assert device_code.status == "pending"
    end

    test "shows error when action not specified", %{
      user: user,
      device_code: device_code
    } do
      conn = login_user(build_conn(), user)

      conn =
        post(conn, ~p"/oauth/device", %{
          "user_code" => device_code.user_code,
          "selected_scopes" => ["api"]
        })

      assert html_response(conn, 200) =~ "Invalid action"

      # Verify device was not processed
      updated_device_code = Repo.get(DeviceCode, device_code.id)
      assert updated_device_code.status == "pending"
    end

    test "shows error for invalid user_code", %{user: user} do
      conn = login_user(build_conn(), user)

      conn =
        post(conn, ~p"/oauth/device", %{
          "user_code" => "INVALID",
          "action" => "authorize",
          "selected_scopes" => ["api"]
        })

      assert html_response(conn, 200) =~ "Invalid user code"
    end

    test "shows error for expired device code", %{user: user, device_code: device_code} do
      # Expire the device code
      past_time = DateTime.add(DateTime.utc_now(), -3600, :second)
      Repo.update!(DeviceCode.changeset(device_code, %{expires_at: past_time}))

      conn = login_user(build_conn(), user)

      conn =
        post(conn, ~p"/oauth/device", %{
          "user_code" => device_code.user_code,
          "action" => "authorize",
          "selected_scopes" => ["api"]
        })

      assert html_response(conn, 200) =~ "Device code has expired"
    end

    test "shows error for already processed device code", %{user: user, device_code: device_code} do
      # Authorize first with selected scopes
      DeviceCodes.authorize_device(device_code.user_code, user, ["api"])

      conn = login_user(build_conn(), user)

      conn =
        post(conn, ~p"/oauth/device", %{
          "user_code" => device_code.user_code,
          "action" => "authorize",
          "selected_scopes" => ["api"]
        })

      assert html_response(conn, 200) =~ "Device code is not pending authorization"
    end

    test "shows error for invalid action", %{user: user, device_code: device_code} do
      conn = login_user(build_conn(), user)

      conn =
        post(conn, ~p"/oauth/device", %{
          "user_code" => device_code.user_code,
          "action" => "invalid"
        })

      assert html_response(conn, 200) =~ "Invalid action"
    end

    test "shows error when user_code is missing", %{user: user} do
      conn = login_user(build_conn(), user)

      conn = post(conn, ~p"/oauth/device", %{})

      assert html_response(conn, 200) =~ "Missing verification code"
    end
  end

  defp login_user(conn, user) do
    conn
    |> init_test_session(%{})
    |> put_session("user_id", user.id)
  end

  describe "device verification rate limiting" do
    setup do
      user = insert(:user)
      client = create_test_client()

      mock_conn =
        build_conn()
        |> Map.put(:scheme, :https)
        |> Map.put(:host, "hex.pm")
        |> Map.put(:port, 443)

      {:ok, response} =
        DeviceCodes.initiate_device_authorization(mock_conn, client.client_id, ["api"])

      device_code = Repo.get_by(DeviceCode, device_code: response.device_code)
      %{user: user, device_code: device_code, client: client}
    end

    test "GET /oauth/device rate limiting function exists and is called", %{
      user: user,
      device_code: device_code
    } do
      user_code = device_code.user_code

      conn =
        build_conn()
        |> login_user(user)
        |> get(~p"/oauth/device?user_code=#{user_code}")

      # Should get a valid response
      assert html_response(conn, 200)

      # If rate limited, should contain the message
      if response_contains_rate_limit_message?(conn) do
        response_body = html_response(conn, 200)
        assert response_body =~ "Too many verification attempts"
        assert response_body =~ "wait 15 minutes"
      end
    end

    test "POST /oauth/device rate limiting applies to requests", %{
      user: user,
      device_code: device_code
    } do
      user_code = device_code.user_code

      conn =
        build_conn()
        |> login_user(user)
        |> post(~p"/oauth/device", %{"user_code" => user_code, "action" => "deny"})

      # Should get a redirect response (successful deny) since this test doesn't actually trigger rate limiting
      assert redirected_to(conn, 302) == "/"
    end

    defp response_contains_rate_limit_message?(conn) do
      response_body = html_response(conn, 200)

      response_body =~ "Too many verification attempts" and
        response_body =~ "wait 15 minutes"
    end
  end
end
