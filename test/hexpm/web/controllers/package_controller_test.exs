defmodule Hexpm.Web.PackageControllerTest do
  use Hexpm.ConnCase, async: true

  setup do
    package1 = insert(:package)
    package2 = insert(:package)
    insert(:release, package: package1, version: "0.0.1", meta: build(:release_metadata, app: package1.name))
    insert(:release, package: package1, version: "0.0.2", meta: build(:release_metadata, app: package1.name))
    insert(:release, package: package1, version: "0.0.3-dev", meta: build(:release_metadata, app: package1.name))
    insert(:release, package: package2, version: "1.0.0", meta: build(:release_metadata, app: package2.name))
    %{package1: package1, package2: package2}
  end

  describe "GET /packages" do
    test "index", %{package1: package1, package2: package2} do
      conn = get build_conn(), "/packages"
      result = response(conn, 200)
      assert result =~ ~r/#{package1.name}.*0.0.2/
      assert result =~ package2.name
    end

    test "index with letter", %{package1: package1, package2: package2} do
      conn = get build_conn(), "/packages?letter=#{String.at(package1.name, 0)}"
      assert response(conn, 200) =~ package1.name

      conn = get build_conn(), "/packages?letter=#{String.at(package2.name, 0)}"
      assert response(conn, 200) =~ package2.name
    end

    test "index with search query", %{package1: package1, package2: package2} do
      conn = get build_conn(), "/packages?search=#{package1.name}"
      assert response(conn, 200) =~ ~r/#{package1.name}.*0.0.2/

      conn = get build_conn(), "/packages?search=#{package2.name}"
      assert response(conn, 200) =~ ~r/#{package2.name}.*1.0.0/
    end
  end

  describe "GET /packages/:name" do
    test "show package", %{package1: package1} do
      conn = get build_conn(), "/packages/#{package1.name}"
      assert response(conn, 200) =~ escape(~s({:#{package1.name}, "~> 0.0.2"}))
    end
  end

  describe "GET /packages/:name/:version" do
    test "show package version", %{package1: package1} do
      conn = get build_conn(), "/packages/#{package1.name}/0.0.1"
      assert response(conn, 200) =~ escape(~s({:#{package1.name}, "~> 0.0.1"}))
    end
  end

  defp escape(html) do
    {:safe, safe} = Phoenix.HTML.html_escape(html)
    safe
  end
end
