defmodule HexpmWeb.API.RepositoryControllerTest do
  use HexpmWeb.ConnCase, async: true

  setup do
    repo_user = insert(:user)
    user = insert(:user)
    repository1 = insert(:repository)
    repository2 = insert(:repository)
    insert(:organization_user, user: repo_user, organization: repository1.organization)
    %{repo_user: repo_user, user: user, repository1: repository1, repository2: repository2}
  end

  describe "GET /api/repos" do
    test "not authorized" do
      conn = get(build_conn(), "api/repos")
      result = json_response(conn, 200)
      assert length(result) == 1
    end

    test "authorized", %{repo_user: repo_user} do
      result =
        build_conn()
        |> put_req_header("authorization", key_for(repo_user))
        |> get("api/repos")
        |> json_response(200)

      assert length(result) == 2
    end
  end

  describe "GET /api/repos/:repository" do
    test "not authorized", %{user: user, repository2: repository2} do
      conn = get(build_conn(), "api/repos/hexpm")
      result = json_response(conn, 200)
      assert result["name"] == "hexpm"

      build_conn()
      |> put_req_header("authorization", key_for(user))
      |> get("api/repos/#{repository2.name}")
      |> response(404)

      build_conn()
      |> get("api/repos/#{repository2.name}")
      |> response(404)
    end

    test "authorized", %{repo_user: repo_user, repository1: repository1} do
      result =
        build_conn()
        |> put_req_header("authorization", key_for(repo_user))
        |> get("api/repos/#{repository1.name}")
        |> json_response(200)

      assert result["name"] == repository1.name
    end
  end
end
