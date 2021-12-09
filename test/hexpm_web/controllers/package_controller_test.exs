defmodule HexpmWeb.PackageControllerTest do
  use HexpmWeb.ConnCase, async: true

  setup do
    user1 = insert(:user)
    user2 = insert(:user)

    repository1 = insert(:repository)
    repository2 = insert(:repository)

    package1 = insert(:package)
    package2 = insert(:package)
    package3 = insert(:package, repository_id: repository1.id)
    package4 = insert(:package, repository_id: repository2.id)
    package5 = insert(:package, name: "with_underscore")

    insert(
      :release,
      package: package1,
      version: "0.0.1",
      meta: build(:release_metadata, app: package1.name),
      has_docs: true
    )

    insert(
      :release,
      package: package1,
      version: "0.0.2",
      meta: build(:release_metadata, app: package1.name),
      has_docs: nil
    )

    insert(
      :release,
      package: package1,
      version: %Version{major: 0, minor: 0, patch: 3, pre: ["dev", 0, 1]},
      meta: build(:release_metadata, app: package1.name),
      has_docs: true
    )

    insert(
      :release,
      package: package2,
      version: "1.0.0",
      meta: build(:release_metadata, app: package2.name)
    )

    insert(
      :release,
      package: package3,
      version: "0.0.1",
      meta: build(:release_metadata, app: package3.name)
    )

    insert(
      :release,
      package: package4,
      version: "0.0.1",
      meta: build(:release_metadata, app: package4.name)
    )

    insert(
      :release,
      package: package5,
      version: "0.0.1",
      meta: build(:release_metadata, app: package5.name)
    )

    insert(:organization_user, user: user1, organization: repository1.organization)

    %{
      package1: package1,
      package2: package2,
      package3: package3,
      package4: package4,
      package5: package5,
      repository1: repository1,
      repository2: repository2,
      user1: user1,
      user2: user2
    }
  end

  describe "GET /packages" do
    test "list all", %{package1: package1, package2: package2} do
      conn = get(build_conn(), "/packages")
      result = response(conn, 200)
      assert result =~ ~r/#{package1.name}.*0.0.2/s
      assert result =~ package2.name
    end

    test "search with letter", %{package1: package1, package2: package2} do
      conn = get(build_conn(), "/packages?letter=#{String.at(package1.name, 0)}")
      assert response(conn, 200) =~ package1.name

      conn = get(build_conn(), "/packages?letter=#{String.at(package2.name, 0)}")
      assert response(conn, 200) =~ package2.name
    end

    test "search with search query", %{package1: package1, package2: package2} do
      conn = get(build_conn(), "/packages?search=#{package1.name}")
      assert response(conn, 200) =~ ~r/#{package1.name}.*0.0.2/s

      conn = get(build_conn(), "/packages?search=#{package2.name}")
      assert response(conn, 200) =~ ~r/#{package2.name}.*1.0.0/s
    end

    test "search with whitespace", %{package5: package5} do
      conn = get(build_conn(), "/packages?search=with underscore")
      assert response(conn, 200) =~ "exact-match"
      assert response(conn, 200) =~ package5.name
      refute response(conn, 200) =~ "no-results"
    end

    test "search without match" do
      conn = get(build_conn(), "/packages?search=nonexistent")
      assert response(conn, 200) =~ "no-results"
      refute response(conn, 200) =~ "exact-match"
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
      conn = get(build_conn(), "/packages/#{package1.name}")
      assert response(conn, 200) =~ escape(~s({:#{package1.name}, "~> 0.0.2"}))
    end

    test "package name is case sensitive", %{package1: package1} do
      get(build_conn(), "/packages/#{String.upcase(package1.name)}")
      |> response(404)
    end

    test "show package requires repository", %{package3: package3} do
      build_conn()
      |> get("/packages/#{package3.name}")
      |> response(404)
    end

    test "show first few audit_logs related to this package", %{package1: package} do
      insert(:audit_log, action: "docs.publish", params: %{package: %{id: package.id}})
      insert(:audit_log, action: "docs.revert", params: %{package: %{id: package.id}})
      insert(:audit_log, action: "owner.add", params: %{package: %{id: package.id}})
      insert(:audit_log, action: "owner.remove", params: %{package: %{id: package.id}})
      insert(:audit_log, action: "release.publish", params: %{package: %{id: package.id}})
      insert(:audit_log, action: "release.revert", params: %{package: %{id: package.id}})
      insert(:audit_log, action: "release.retire", params: %{package: %{id: package.id}})
      insert(:audit_log, action: "release.unretire", params: %{package: %{id: package.id}})

      html_response =
        build_conn()
        |> get("/packages/#{package.name}")
        |> html_response(200)

      assert html_response =~ "Publish doc"
      assert html_response =~ "Revert doc"
      assert html_response =~ "Add owner"
      assert html_response =~ "Remove owner"
      assert html_response =~ "Publish release"
      assert html_response =~ "Revert release"
      assert html_response =~ "Retire release"
      assert html_response =~ "Unretire release"
    end

    test "show latest valid version documentation link", %{package1: package} do
      html_response =
        build_conn()
        |> get("/packages/#{package.name}")
        |> html_response(200)

      assert html_response =~ "0.0.1.tar.gz"
      refute html_response =~ "0.0.2.tar.gz"
      refute html_response =~ "0.0.3-dev.0.1.tar.gz"
    end
  end

  describe "GET /packages/:name/:version" do
    test "show package version", %{package1: package1} do
      conn = get(build_conn(), "/packages/#{package1.name}/0.0.1")
      assert response(conn, 200) =~ escape(~s({:#{package1.name}, "~> 0.0.1"}))
    end

    test "show publisher info", %{package1: package1} do
      release =
        insert(
          :release,
          package: package1,
          publisher: build(:user),
          version: "0.1.0",
          meta: build(:release_metadata, app: package1.name)
        )

      conn = get(build_conn(), "/packages/#{package1.name}/0.1.0")
      assert response(conn, 200) =~ release.publisher.username
    end

    test "show package from other repository", %{
      user1: user1,
      repository1: repository1,
      package3: package3
    } do
      conn =
        build_conn()
        |> test_login(user1)
        |> get("/packages/#{repository1.name}/#{package3.name}")

      assert response(conn, 200) =~
               escape(~s({:#{package3.name}, "~> 0.0.1", organization: "#{repository1.name}"}))
    end

    test "dont show private package", %{
      user2: user2,
      repository1: repository1,
      package3: package3
    } do
      build_conn()
      |> test_login(user2)
      |> get("/packages/#{repository1.name}/#{package3.name}")
      |> response(404)
    end

    test "show hexpm package", %{package1: package1} do
      conn = get(build_conn(), "/packages/hexpm/#{package1.name}")
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
      conn = get(build_conn(), "/packages/hexpm/#{package1.name}/0.0.1")
      assert response(conn, 200) =~ escape(~s({:#{package1.name}, "~> 0.0.1"}))
    end

    test "show package", %{user1: user1, repository1: repository1, package3: package3} do
      conn =
        build_conn()
        |> test_login(user1)
        |> get("/packages/#{repository1.name}/#{package3.name}/0.0.1")

      assert response(conn, 200) =~
               escape(~s({:#{package3.name}, "~> 0.0.1", organization: "#{repository1.name}"}))
    end

    test "repository name is case sensitive", %{
      user1: user1,
      repository1: repository1,
      package3: package3
    } do
      build_conn()
      |> test_login(user1)
      |> get("/packages/#{String.upcase(repository1.name)}/#{package3.name}/0.0.1")
      |> response(404)
    end

    test "dont show private package", %{
      user2: user2,
      repository1: repository1,
      package3: package3
    } do
      build_conn()
      |> test_login(user2)
      |> get("/packages/#{repository1.name}/#{package3.name}/0.0.1")
      |> response(404)
    end
  end

  describe "GET /packages/:name/audit_logs" do
    test "sets title correctly" do
      _package = insert(:package, name: "Test")

      conn = get(build_conn(), "/packages/Test/audit_logs")

      assert response(conn, :ok) =~ "Recent Activities for Test"
    end

    test "renders audit_logs correctly" do
      package = insert(:package, name: "Test")
      insert(:audit_log, action: "docs.publish", params: %{package: %{id: package.id}})

      conn = get(build_conn(), "/packages/Test/audit_logs")

      assert response(conn, :ok) =~ "Publish documentation"
    end
  end

  describe "GET /packages/:repository/:name/audit_logs" do
    test "requires access to this repository" do
      repository = insert(:repository, name: "Repo")
      _package = insert(:package, repository_id: repository.id, name: "Test")

      conn = get(build_conn(), "/packages/Repo/Test/audit_logs")

      assert response(conn, :not_found)
    end
  end

  defp escape(html) do
    {:safe, safe} = Phoenix.HTML.html_escape(html)
    IO.iodata_to_binary(safe)
  end
end
