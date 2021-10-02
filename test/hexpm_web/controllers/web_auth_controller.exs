defmodule HexpmWeb.WebAuthControllerTest do
  use HexpmWeb.ConnCase, async: true

  @test %{scope: "write"}

  setup_all do
    _ = start_supervised(Hexpm.WebAuth)
    :ok
  end

  setup do
    conn =
      build_conn()
      |> put_req_header("accept", "application/json")

    %{conn: conn}
  end

  describe "POST /web_auth/code" do
    test "returns a valid response", %{conn: conn} do
      response =
        post(conn, Routes.web_auth_path(conn, :code, @test))
        |> json_response(200)

      assert response["device_code"]
      assert response["user_code"]
      assert response["verification_uri"]
      assert response["access_token_uri"]
      assert response["verification_expires_in"]
      assert response["token_access_expires_in"]
    end

    test "returns a verification_uri that is an endpoint", %{conn: conn} do
      {:ok, verification_uri} =
        post(conn, Routes.web_auth_path(conn, :code, @test))
        |> json_response(200)
        |> Map.fetch("verification_uri")

      assert verification_uri =~ Routes.web_auth_path(conn, :show)
    end

    test "returns a access_token_uri that is an endpoint", %{conn: conn} do
      {:ok, access_token_uri} =
        post(conn, Routes.web_auth_path(conn, :code, @test))
        |> json_response(200)
        |> Map.fetch("access_token_uri")

      assert access_token_uri =~ Routes.web_auth_path(conn, :access_token)
    end

    test "returns an error on invalid scope", %{conn: conn} do
      response =
        post(conn, Routes.web_auth_path(conn, :code, %{"scope" => "foo"}))
        |> json_response(422)

      assert response == %{"error" => "invalid scope"}
    end

    test "returns an error on invalid parameters", %{conn: conn} do
      response =
        post(conn, Routes.web_auth_path(conn, :code, %{"foo" => "bar"}))
        |> json_response(400)

      assert response == %{"error" => "invalid parameters"}
    end
  end

  describe "POST /web_auth/submit" do
    setup :setup_users

    test "redirects to sucess page on valid user code", c do
      {:ok, user_code} =
        post(build_conn(), Routes.web_auth_path(build_conn(), :code, @test))
        |> json_response(200)
        |> Map.fetch("user_code")

      request = %{"user_code" => user_code, "user_id" => c.user.id}

      conn = post(c.conn, Routes.web_auth_path(c.conn, :submit, request))

      assert redirected_to(conn, 200) =~ Routes.web_auth_path(conn, :success)
      assert html_response(conn, 200) =~ "Congratulations, you're all set!"
    end

    test "returns an error on an invalid user code", c do
      _user_code = post(build_conn(), Routes.web_auth_path(build_conn(), :code, @test))

      request = %{"user_code" => "bad-code", "user_id" => c.user.id}

      page =
        post(c.conn, Routes.web_auth_path(c.conn, :submit, request))
        |> html_response(200)

      assert get_flash(page) =~ "Please make sure you entered the user code correctly."
    end
  end

  def setup_users(context) do
    user = insert(:user)
    organization = insert(:organization)
    insert(:organization_user, organization: organization, user: user)
    Map.merge(context, %{user: user, organization: organization})
  end
end
