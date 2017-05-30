defmodule Hexpm.Web.API.RepositoryControllerTest do
  use Hexpm.ConnCase, async: true

  setup do
    user = insert(:user)
    repository1 = insert(:repository, public: true)
    repository2 = insert(:repository, public: false)
    insert(:repository, public: false)
    insert(:repostory_user, user: user, repository: repository2)
    %{user: user, repository1: repository1, repository2: repository2}
  end

  describe "GET /api/repositories" do
    test "not authorized" do
      conn = get build_conn(), "api/repositories"
      result = json_response(conn, 200)
      assert length(result) == 2
    end

    test "authorized", %{user: user} do
      result =
        build_conn()
        |> put_req_header("authorization", key_for(user))
        |> get("api/repositories")
        |> json_response(200)
      assert length(result) == 3
    end
  end

  describe "GET /api/repositories/:repository" do
    test "not authorized", %{repository1: repository1, repository2: repository2} do
      conn = get build_conn(), "api/repositories/#{repository1.name}"
      result = json_response(conn, 200)
      assert result["name"] == repository1.name

      conn = get build_conn(), "api/repositories/#{repository2.name}"
      response(conn, 403)
    end

    test "authorized", %{user: user, repository2: repository2} do
      result =
        build_conn()
        |> put_req_header("authorization", key_for(user))
        |> get("api/repositories/#{repository2.name}")
        |> json_response(200)
      assert result["name"] == repository2.name
    end
  end
end
