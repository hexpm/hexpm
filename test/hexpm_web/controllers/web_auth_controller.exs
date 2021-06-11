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
end
