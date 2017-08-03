defmodule Hexpm.Web.API.PackageControllerTest do
  use Hexpm.ConnCase, async: true

  setup do
    user = insert(:user)
    repository = insert(:repository)
    package1 = insert(:package, inserted_at: ~N[2030-01-01 00:00:00])
    package2 = insert(:package, updated_at: ~N[2030-01-01 00:00:00])
    package3 = insert(:package, repository_id: repository.id, updated_at: ~N[2030-01-01 00:00:00])
    insert(:release, package: package1, version: "0.0.1")
    insert(:release, package: package3, version: "0.0.1")
    insert(:repository_user, repository: repository, user: user)

    %{
      package1: package1,
      package2: package2,
      package3: package3,
      repository: repository,
      user: user
    }
  end

  describe "GET /api/packages" do
    test "multiple packages", %{package1: package1} do
      conn = get build_conn(), "api/packages"
      result = json_response(conn, 200)
      assert length(result) == 2
      releases = List.first(result)["releases"]

      for release <- releases do
        assert length(Map.keys(release)) == 2
        assert Map.has_key?(release, "url")
        assert Map.has_key?(release, "version")
      end

      conn = get build_conn(), "api/packages?search=#{package1.name}"
      result = json_response(conn, 200)
      assert length(result) == 1

      conn = get build_conn(), "api/packages?search=name%3A#{package1.name}*"
      result = json_response(conn, 200)
      assert length(result) == 1

      conn = get build_conn(), "api/packages?page=1"
      result = json_response(conn, 200)
      assert length(result) == 2

      conn = get build_conn(), "api/packages?page=2"
      result = json_response(conn, 200)
      assert length(result) == 0
    end

    test "sort order", %{package1: package1, package2: package2} do
      conn = get build_conn(), "api/packages?sort=updated_at"
      result = json_response(conn, 200)
      assert hd(result)["name"] == package2.name

      conn = get build_conn(), "api/packages?sort=inserted_at"
      result = json_response(conn, 200)
      assert hd(result)["name"] == package1.name
    end

    test "show private packages", %{user: user, package3: package3} do
      result =
        build_conn()
        # TODO: change to web_login/api_login helper
        |> put_req_header("authorization", key_for(user))
        |> get("api/packages")
        |> json_response(200)

      assert length(result) == 3
      assert package3.name in Enum.map(result, & &1["name"])
    end
  end

  describe "GET /api/packages/:name" do
    test "get package", %{package1: package1} do
      conn = get build_conn(), "api/packages/#{package1.name}"
      result = json_response(conn, 200)
      assert result["name"] == package1.name

      release = List.first(result["releases"])
      assert release["url"] =~ "/api/packages/#{package1.name}/releases/0.0.1"
      assert release["version"] == "0.0.1"
    end

    test "get package for non namespaced private repository", %{user: user, package3: package3} do
      build_conn()
      |> put_req_header("authorization", key_for(user))
      |> get("api/packages/#{package3.name}")
      |> json_response(404)
    end

    test "get package for unautenticated private repository", %{repository: repository, package3: package3} do
      build_conn()
      |> get("api/repos/#{repository.name}/packages/#{package3.name}")
      |> json_response(403)
    end

    test "get package returns 403 for unknown repository", %{package1: package1} do
      build_conn()
      |> get("api/repos/UNKNOWN_REPOSITORY/packages/#{package1.name}")
      |> json_response(403)
    end

    test "get package returns 403 for unknown package if you are not authorized", %{repository: repository} do
      build_conn()
      |> get("api/repos/#{repository.name}/packages/UNKNOWN_PACKAGE")
      |> json_response(403)
    end

    test "get package returns 404 for unknown package if you are authorized", %{user: user, repository: repository} do
      build_conn()
      |> put_req_header("authorization", key_for(user))
      |> get("api/repos/#{repository.name}/packages/UNKNOWN_PACKAGE")
      |> json_response(404)
    end

    test "get package for autenticated private repository", %{user: user, repository: repository, package3: package3} do
      result =
        build_conn()
        |> put_req_header("authorization", key_for(user))
        |> get("api/repos/#{repository.name}/packages/#{package3.name}")
        |> json_response(200)

      assert result["name"] == package3.name
      assert result["repository"] == repository.name
    end
  end
end
