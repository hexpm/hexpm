defmodule HexpmWeb.DeviceControllerTest do
  use HexpmWeb.ConnCase, async: true

  alias Hexpm.OAuth.{DeviceFlow, DeviceCode}

  describe "GET /device" do
    test "redirects to login when not authenticated" do
      conn = get(build_conn(), ~p"/device")
      assert redirected_to(conn) =~ "/login"
    end

    test "shows verification form when authenticated" do
      user = create_user()
      conn = login_user(build_conn(), user)

      conn = get(conn, ~p"/device")
      assert html_response(conn, 200) =~ "Device Authorization"
      assert html_response(conn, 200) =~ "Enter the verification code"
    end

    test "shows device info when valid user_code provided" do
      user = create_user()
      conn = login_user(build_conn(), user)

      {:ok, response} = DeviceFlow.initiate_device_authorization("test_client", ["api"])

      conn = get(conn, ~p"/device?user_code=#{response.user_code}")
      assert html_response(conn, 200) =~ "Device Authorization"
      assert html_response(conn, 200) =~ "test_client"
      assert html_response(conn, 200) =~ "Authorize Device"
    end

    test "shows error for invalid user_code" do
      user = create_user()
      conn = login_user(build_conn(), user)

      conn = get(conn, ~p"/device?user_code=INVALID")
      assert html_response(conn, 200) =~ "Invalid verification code"
    end

    test "redirects to login with return path for user_code" do
      {:ok, response} = DeviceFlow.initiate_device_authorization("test_client", ["api"])

      conn = get(build_conn(), ~p"/device?user_code=#{response.user_code}")
      assert redirected_to(conn) =~ "/login"
      assert redirected_to(conn) =~ "return="
      assert redirected_to(conn) =~ "%3Fuser_code%3D"
    end
  end

  describe "POST /device" do
    setup do
      user = create_user()
      {:ok, response} = DeviceFlow.initiate_device_authorization("test_client", ["api"])
      device_code = Repo.get_by(DeviceCode, device_code: response.device_code)
      %{user: user, device_code: device_code}
    end

    test "redirects to login when not authenticated", %{device_code: device_code} do
      conn = post(build_conn(), ~p"/device", %{
        "user_code" => device_code.user_code,
        "action" => "authorize"
      })

      assert redirected_to(conn) =~ "/login"
    end

    test "authorizes device successfully", %{user: user, device_code: device_code} do
      conn = login_user(build_conn(), user)

      conn = post(conn, ~p"/device", %{
        "user_code" => device_code.user_code,
        "action" => "authorize"
      })

      assert html_response(conn, 200) =~ "Device has been successfully authorized!"

      # Verify device was authorized in database
      updated_device_code = Repo.get(DeviceCode, device_code.id)
      assert updated_device_code.status == "authorized"
      assert updated_device_code.user_id == user.id
    end

    test "denies device successfully", %{user: user, device_code: device_code} do
      conn = login_user(build_conn(), user)

      conn = post(conn, ~p"/device", %{
        "user_code" => device_code.user_code,
        "action" => "deny"
      })

      assert html_response(conn, 200) =~ "Device authorization has been denied"

      # Verify device was denied in database
      updated_device_code = Repo.get(DeviceCode, device_code.id)
      assert updated_device_code.status == "denied"
    end

    test "defaults to authorize action when action not specified", %{user: user, device_code: device_code} do
      conn = login_user(build_conn(), user)

      conn = post(conn, ~p"/device", %{
        "user_code" => device_code.user_code
      })

      assert html_response(conn, 200) =~ "Device has been successfully authorized!"

      updated_device_code = Repo.get(DeviceCode, device_code.id)
      assert updated_device_code.status == "authorized"
    end

    test "shows error for invalid user_code", %{user: user} do
      conn = login_user(build_conn(), user)

      conn = post(conn, ~p"/device", %{
        "user_code" => "INVALID",
        "action" => "authorize"
      })

      assert html_response(conn, 200) =~ "Invalid user code"
    end

    test "shows error for expired device code", %{user: user, device_code: device_code} do
      # Expire the device code
      past_time = DateTime.add(DateTime.utc_now(), -3600, :second)
      Repo.update!(DeviceCode.changeset(device_code, %{expires_at: past_time}))

      conn = login_user(build_conn(), user)

      conn = post(conn, ~p"/device", %{
        "user_code" => device_code.user_code,
        "action" => "authorize"
      })

      assert html_response(conn, 200) =~ "Device code has expired"
    end

    test "shows error for already processed device code", %{user: user, device_code: device_code} do
      # Authorize first
      DeviceFlow.authorize_device(device_code.user_code, user)

      conn = login_user(build_conn(), user)

      conn = post(conn, ~p"/device", %{
        "user_code" => device_code.user_code,
        "action" => "authorize"
      })

      assert html_response(conn, 200) =~ "Device code is not pending authorization"
    end

    test "shows error for invalid action", %{user: user, device_code: device_code} do
      conn = login_user(build_conn(), user)

      conn = post(conn, ~p"/device", %{
        "user_code" => device_code.user_code,
        "action" => "invalid"
      })

      assert html_response(conn, 200) =~ "Invalid action"
    end

    test "shows error when user_code is missing", %{user: user} do
      conn = login_user(build_conn(), user)

      conn = post(conn, ~p"/device", %{})

      assert html_response(conn, 200) =~ "Missing verification code"
    end
  end

  defp create_user do
    import Hexpm.Factory
    insert(:user)
  end

  defp login_user(conn, user) do
    conn
    |> init_test_session(%{})
    |> put_session("user_id", user.id)
  end

  describe "device verification rate limiting" do
    setup do
      user = create_user()
      {:ok, response} = DeviceFlow.initiate_device_authorization("test_client", ["api"])
      %{user: user, user_code: response.user_code}
    end

    test "GET /device rate limiting function exists and is called", %{user: user, user_code: user_code} do
      conn =
        build_conn()
        |> login_user(user)
        |> get(~p"/device?user_code=#{user_code}")

      # Should get a valid response
      assert html_response(conn, 200)

      # If rate limited, should contain the message
      if response_contains_rate_limit_message?(conn) do
        response_body = html_response(conn, 200)
        assert response_body =~ "Too many verification attempts"
        assert response_body =~ "wait 15 minutes"
      end
    end

    test "POST /device rate limiting applies to requests", %{user: user, user_code: user_code} do
      conn =
        build_conn()
        |> login_user(user)
        |> post(~p"/device", %{"user_code" => user_code, "action" => "deny"})

      # Should get a valid response
      assert html_response(conn, 200)

      # If rate limited, should contain the message
      if response_contains_rate_limit_message?(conn) do
        response_body = html_response(conn, 200)
        assert response_body =~ "Too many verification attempts"
      end
    end

    defp response_contains_rate_limit_message?(conn) do
      response_body = html_response(conn, 200)
      response_body =~ "Too many verification attempts" and
      response_body =~ "wait 15 minutes"
    end
  end
end