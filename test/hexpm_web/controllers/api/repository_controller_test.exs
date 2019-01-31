defmodule HexpmWeb.API.RepositoryControllerTest do
  use HexpmWeb.ConnCase, async: true

  setup do
    user = insert(:user)
    repository1 = insert(:repository, public: false)
    repository2 = insert(:repository, public: false)
    insert(:organization_user, user: user, organization: repository1.organization)
    %{user: user, repository1: repository1, repository2: repository2}
  end

  describe "GET /api/repos" do
    test "not authorized" do
      conn = get(build_conn(), "api/repos")
      result = json_response(conn, 200)
      assert length(result) == 1
    end

    test "authorized", %{user: user} do
      result =
        build_conn()
        |> put_req_header("authorization", key_for(user))
        |> get("api/repos")
        |> json_response(200)

      assert length(result) == 2
    end
  end

  describe "GET /api/repos/:repository" do
    test "not authorized", %{repository2: repository2} do
      conn = get(build_conn(), "api/repos/hexpm")
      result = json_response(conn, 200)
      assert result["name"] == "hexpm"

      conn = get(build_conn(), "api/repos/#{repository2.name}")
      response(conn, 403)
    end

    test "authorized", %{user: user, repository1: repository1} do
      result =
        build_conn()
        |> put_req_header("authorization", key_for(user))
        |> get("api/repos/#{repository1.name}")
        |> json_response(200)

      assert result["name"] == repository1.name
    end
  end
end
