defmodule HexpmWeb.WebAuthControllerTest do
  use HexpmWeb.ConnCase, async: true

  alias Hexpm.Accounts.WebAuth

  setup [:build_conn, :login]

  describe "POST /web_auth/submit" do
    setup [:get_code]

    test "returns found on valid parameters", c do
      request = %{"user_code" => c.request.user_code}

      response =
        c.conn
        |> post(Routes.web_auth_path(c.conn, :submit, request))
        |> html_response(:found)

      assert response =~ "success"
    end

    test "returns an error on an invalid user code", %{conn: conn} do
      response =
        conn
        |> post(Routes.web_auth_path(conn, :submit, %{"user_code" => "bad-code"}))
        |> html_response(:bad_request)

      assert response =~ "invalid user code"
    end

    test "returns an error on invalid parameters", %{conn: conn} do
      response =
        conn
        |> post(Routes.web_auth_path(conn, :code, %{"foo" => "bar"}))
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

    conn = test_login(context.conn, user)

    Map.merge(context, %{user: user, organization: organization, conn: conn})
  end

  def get_code(context) do
    {:ok, request} = WebAuth.get_code("test-key")

    Map.merge(context, %{request: request})
  end
end
