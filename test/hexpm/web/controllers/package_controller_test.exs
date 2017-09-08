defmodule Hexpm.Web.PackageControllerTest do
  use Hexpm.ConnCase, async: true

  setup do
    user1 = insert(:user)
    user2 = insert(:user)

    repository1 = insert(:repository)
    repository2 = insert(:repository)

    package1 = insert(:package)
    package2 = insert(:package)
    package3 = insert(:package, repository_id: repository1.id)
    package4 = insert(:package, repository_id: repository2.id)

    insert(:release, package: package1, version: "0.0.1", meta: build(:release_metadata, app: package1.name))
    insert(:release, package: package1, version: "0.0.2", meta: build(:release_metadata, app: package1.name))
    insert(:release, package: package1, version: "0.0.3-dev", meta: build(:release_metadata, app: package1.name))
    insert(:release, package: package2, version: "1.0.0", meta: build(:release_metadata, app: package2.name))
    insert(:release, package: package3, version: "0.0.1", meta: build(:release_metadata, app: package3.name))
    insert(:release, package: package4, version: "0.0.1", meta: build(:release_metadata, app: package4.name))

    insert(:repository_user, user: user1, repository: repository1)

    %{
      package1: package1,
      package2: package2,
      package3: package3,
      package4: package4,
      repository1: repository1,
      repository2: repository2,
      user1: user1,
      user2: user2
    }
  end

  describe "GET /packages" do
    test "list all", %{package1: package1, package2: package2} do
      conn = get build_conn(), "/packages"
      result = response(conn, 200)
      assert result =~ ~r/#{package1.name}.*0.0.2/s
      assert result =~ package2.name
    end

    test "search with letter", %{package1: package1, package2: package2} do
      conn = get build_conn(), "/packages?letter=#{String.at(package1.name, 0)}"
      assert response(conn, 200) =~ package1.name

      conn = get build_conn(), "/packages?letter=#{String.at(package2.name, 0)}"
      assert response(conn, 200) =~ package2.name
    end

    test "search with search query", %{package1: package1, package2: package2} do
      conn = get build_conn(), "/packages?search=#{package1.name}"
      assert response(conn, 200) =~ ~r/#{package1.name}.*0.0.2/s

      conn = get build_conn(), "/packages?search=#{package2.name}"
      assert response(conn, 200) =~ ~r/#{package2.name}.*1.0.0/s
    end

    test "list private packages", %{
      user1: user1,
      package3: package3,
      package4: package4,
      repository1: repository1,
      repository2: repository2
    } do
      conn =
        build_conn()
        |> test_login(user1)
        |> get("/packages")

      result = response(conn, 200)
      assert result =~ "#{repository1.name} / #{package3.name}"
      refute result =~ "#{repository2.name} / #{package4.name}"
    end
  end

  describe "GET /packages/:name" do
    test "show package", %{package1: package1} do
      conn = get build_conn(), "/packages/#{package1.name}"
      assert response(conn, 200) =~ escape(~s({:#{package1.name}, "~> 0.0.2"}))
    end

    test "show package requires repository", %{package3: package3} do
      build_conn()
      |> get("/packages/#{package3.name}")
      |> response(404)
    end
  end

  describe "GET /packages/:name/:version" do
    test "show package version", %{package1: package1} do
      conn = get build_conn(), "/packages/#{package1.name}/0.0.1"
      assert response(conn, 200) =~ escape(~s({:#{package1.name}, "~> 0.0.1"}))
    end

    test "show package from other repository", %{user1: user1, repository1: repository1, package3: package3} do
      conn =
        build_conn()
        |> test_login(user1)
        |> get("/packages/#{repository1.name}/#{package3.name}")
      assert response(conn, 200) =~ escape(~s({:#{package3.name}, "~> 0.0.1", organization: "#{repository1.name}"}))
    end

    test "dont show private package", %{user2: user2, repository1: repository1, package3: package3} do
      build_conn()
      |> test_login(user2)
      |> get("/packages/#{repository1.name}/#{package3.name}")
      |> response(404)
    end

    test "show hexpm package", %{package1: package1} do
      conn = get build_conn(), "/packages/hexpm/#{package1.name}"
      assert response(conn, 200) =~ escape(~s({:#{package1.name}, "~> 0.0.2"}))
    end

    test "show package requires repository", %{package3: package3} do
      build_conn()
      |> get("/packages/#{package3.name}/0.0.1")
      |> response(404)
    end
  end

  describe "GET /packages/:repository/:name/:version" do
    test "show hexpm package", %{package1: package1} do
      conn = get build_conn(), "/packages/hexpm/#{package1.name}/0.0.1"
      assert response(conn, 200) =~ escape(~s({:#{package1.name}, "~> 0.0.1"}))
    end

    test "show package", %{user1: user1, repository1: repository1, package3: package3} do
      conn =
        build_conn()
        |> test_login(user1)
        |> get("/packages/#{repository1.name}/#{package3.name}/0.0.1")
      assert response(conn, 200) =~ escape(~s({:#{package3.name}, "~> 0.0.1", organization: "#{repository1.name}"}))
    end

    test "dont show private package", %{user2: user2, repository1: repository1, package3: package3} do
      build_conn()
      |> test_login(user2)
      |> get("/packages/#{repository1.name}/#{package3.name}/0.0.1")
      |> response(404)
    end
  end

  defp escape(html) do
    {:safe, safe} = Phoenix.HTML.html_escape(html)
    safe
  end
end
