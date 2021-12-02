defmodule HexpmWeb.WebAuthControllerTest do
  use HexpmWeb.ConnCase, async: true

  @test %{key_name: "test-key"}

  setup [:build_conn, :login]

  describe "POST /web_auth/code" do
    test "returns a valid response on valid parameters", %{conn: conn} do
      response =
        conn
        |> post(Routes.web_auth_path(conn, :code, @test))
        |> json_response(:ok)

      assert response["device_code"]
      assert response["user_code"]
    end

    test "returns an error on invalid parameters", %{conn: conn} do
      response =
        post(conn, Routes.web_auth_path(conn, :code, %{"foo" => "bar"}))
        |> json_response(:bad_request)

      assert response == %{"error" => "invalid parameters"}
    end
  end

  describe "POST /web_auth/submit" do
    setup [:get_code]

    test "returns ok on valid parameters", c do
      request = %{"user_code" => c.request["user_code"]}

      response =
        c.conn
        |> post(Routes.web_auth_path(c.conn, :submit, request))
        |> json_response(:ok)

      assert response["ok"]
    end

    test "returns an error on an invalid user code", %{conn: conn} do
      response =
        conn
        |> post(Routes.web_auth_path(conn, :submit, %{"user_code" => "bad-code"}))
        |> json_response(:unprocessable_entity)

      assert response["error"] == "invalid user code"
    end

    test "returns an error on invalid parameters", %{conn: conn} do
      response =
        conn
        |> post(Routes.web_auth_path(conn, :code, %{"foo" => "bar"}))
        |> json_response(:bad_request)

      assert response == %{"error" => "invalid parameters"}
    end
  end

  describe "POST /web_auth/access" do
    setup [:get_code, :submit]

    test "returns valid keys on valid device code", c do
      request = %{"device_code" => c.request["device_code"]}

      response =
        c.conn
        |> post(Routes.web_auth_path(c.conn, :access_key, request))
        |> json_response(:ok)

      for key <- ["write_key", "read_key"] do
        url = response[key]

        assert url
        assert get(c.conn, url)
      end
    end

    test "returns an error on invalid device code", c do
      request = %{"device_code" => "bad-code"}

      response =
        c.conn
        |> post(Routes.web_auth_path(c.conn, :access_key, request))
        |> json_response(:unprocessable_entity)

      assert response == %{"error" => "invalid device code"}
    end

    test "returns an error on invalid parameters", c do
      request = %{}

      response =
        c.conn
        |> post(Routes.web_auth_path(c.conn, :access_key, request))
        |> json_response(:bad_request)

      assert response == %{"error" => "invalid parameters"}
    end
  end

  def build_conn(context) do
    Map.merge(context, %{conn: build_conn()})
  end

  def login(context) do
    user = insert(:user)
    organization = insert(:organization)
    insert(:organization_user, organization: organization, user: user)

    # test login
    conn = test_login(context.conn, user)

    Map.merge(context, %{user: user, organization: organization, conn: conn})
  end

  def get_code(context) do
    request =
      post(context.conn, Routes.web_auth_path(context.conn, :code, @test))
      |> json_response(200)

    Map.merge(context, %{request: request})
  end

  def submit(c) do
    request = %{"user_code" => c.request["user_code"]}

    post(c.conn, Routes.web_auth_path(c.conn, :submit, request))

    c
  end
end
