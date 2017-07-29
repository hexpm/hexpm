defmodule Hexpm.Web.API.PackageControllerTest do
  use Hexpm.ConnCase, async: true

  setup do
    package1 = insert(:package, inserted_at: ~N[2030-01-01 00:00:00])
    package2 = insert(:package, updated_at: ~N[2030-01-01 00:00:00])
    insert(:release, package: package1, version: "0.0.1")
    %{package1: package1, package2: package2}
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
  end
end
