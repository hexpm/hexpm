defmodule Hexpm.Web.PackageControllerTest do
  use Hexpm.ConnCase, async: true

  setup do
    package1 = insert(:package, name: "dec_packagecontroller")
    package2 = insert(:package, name: "post_packagecontroller")
    insert(:release, package: package1, version: "0.0.1", meta: build(:release_metadata, app: "dec_packagecontroller"))
    insert(:release, package: package1, version: "0.0.2", meta: build(:release_metadata, app: "dec_packagecontroller"))
    insert(:release, package: package1, version: "0.0.3-dev", meta: build(:release_metadata, app: "dec_packagecontroller"))
    %{package1: package1, package2: package2}
  end

  describe "GET /packages" do
    test "index" do
      conn = get build_conn(), "/packages"
      assert conn.status == 200
      assert conn.resp_body =~ ~r/dec_packagecontroller.*0.0.2/
      assert conn.resp_body =~ ~r/post_packagecontroller/
    end

    test "index with letter" do
      conn = get build_conn(), "/packages?letter=D"
      assert conn.status == 200
      assert conn.resp_body =~ ~r/dec_packagecontroller/
      refute conn.resp_body =~ ~r/post_packagecontroller/

      conn = get build_conn(), "/packages?letter=P"
      assert conn.status == 200
      refute conn.resp_body =~ ~r/dec_packagecontroller/
      assert conn.resp_body =~ ~r/post_packagecontroller/
    end

    test "index with search query" do
      conn = get build_conn(), "/packages?search=dec"
      assert conn.status == 200
      assert conn.resp_body =~ ~r/dec_packagecontroller.*0.0.2/
      refute conn.resp_body =~ ~r/post_packagecontroller/
    end
  end

  describe "GET /packages/:name" do
    test "show package" do
      conn = get build_conn(), "/packages/dec_packagecontroller"
      assert response(conn, 200) =~ escape(~s({:dec_packagecontroller, "~> 0.0.2"}))
    end
  end

  describe "GET /packages/:name/:version" do
    test "show package version" do
      conn = get build_conn(), "/packages/dec_packagecontroller/0.0.1"
      assert response(conn, 200) =~ escape(~s({:dec_packagecontroller, "~> 0.0.1"}))
    end
  end

  defp escape(html) do
    {:safe, safe} = Phoenix.HTML.html_escape(html)
    safe
  end
end
