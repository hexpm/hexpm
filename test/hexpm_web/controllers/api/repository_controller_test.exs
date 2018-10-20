defmodule HexpmWeb.API.RepositoryControllerTest do
  use HexpmWeb.ConnCase, async: true

  setup do
    user = insert(:user)
    organization1 = insert(:organization, public: true)
    organization2 = insert(:organization, public: false)
    insert(:organization, public: false)
    insert(:organization_user, user: user, organization: organization2)
    %{user: user, organization1: organization1, organization2: organization2}
  end

  describe "GET /api/repos" do
    test "not authorized" do
      conn = get(build_conn(), "api/repos")
      result = json_response(conn, 200)
      assert length(result) == 2
    end

    test "authorized", %{user: user} do
      result =
        build_conn()
        |> put_req_header("authorization", key_for(user))
        |> get("api/repos")
        |> json_response(200)

      assert length(result) == 3
    end
  end

  describe "GET /api/repos/:repository" do
    test "not authorized", %{organization1: organization1, organization2: organization2} do
      conn = get(build_conn(), "api/repos/#{organization1.name}")
      result = json_response(conn, 200)
      assert result["name"] == organization1.name

      conn = get(build_conn(), "api/repos/#{organization2.name}")
      response(conn, 403)
    end

    test "authorized", %{user: user, organization2: organization2} do
      result =
        build_conn()
        |> put_req_header("authorization", key_for(user))
        |> get("api/repos/#{organization2.name}")
        |> json_response(200)

      assert result["name"] == organization2.name
    end
  end
end
