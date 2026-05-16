defmodule HexpmWeb.PackageOwnerControllerTest do
  use HexpmWeb.ConnCase, async: true

  alias Hexpm.Repository.Owners

  setup do
    full_owner = insert(:user)
    maintainer = insert(:user)
    non_owner = insert(:user)

    package =
      insert(:package,
        package_owners: [
          build(:package_owner, user: full_owner, level: "full"),
          build(:package_owner, user: maintainer, level: "maintainer")
        ]
      )

    package = Hexpm.Repo.preload(package, :repository)
    %{full_owner: full_owner, maintainer: maintainer, non_owner: non_owner, package: package}
  end

  describe "GET /packages/:name/owners" do
    test "full owner sees management page", %{full_owner: full_owner, package: package} do
      conn =
        build_conn()
        |> test_login(full_owner)
        |> get("/packages/#{package.name}/owners")

      assert html_response(conn, 200) =~ "Current owners"
    end

    test "redirects to /sudo when no sudo mode", %{full_owner: full_owner, package: package} do
      conn =
        build_conn()
        |> test_login(full_owner, sudo: false)
        |> get("/packages/#{package.name}/owners")

      assert redirected_to(conn) =~ "/sudo"
    end

    test "maintainer is forbidden", %{maintainer: maintainer, package: package} do
      conn =
        build_conn()
        |> test_login(maintainer)
        |> get("/packages/#{package.name}/owners")

      assert conn.status == 403
    end

    test "non-owner is forbidden", %{non_owner: non_owner, package: package} do
      conn =
        build_conn()
        |> test_login(non_owner)
        |> get("/packages/#{package.name}/owners")

      assert conn.status == 403
    end

    test "requires login", %{package: package} do
      conn = get(build_conn(), "/packages/#{package.name}/owners")
      assert redirected_to(conn) =~ "/login"
    end
  end

  describe "POST /packages/:name/owners (direct add)" do
    test "full owner with sudo adds user by username", %{
      full_owner: full_owner,
      non_owner: non_owner,
      package: package
    } do
      conn =
        build_conn()
        |> test_login(full_owner, sudo: true)
        |> post("/packages/#{package.name}/owners", %{"username" => non_owner.username})

      assert redirected_to(conn) == "/packages/#{package.name}/owners"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "added as owner"
      assert Owners.get(package, non_owner)
    end

    test "redirects to /sudo when no sudo mode", %{
      full_owner: full_owner,
      non_owner: non_owner,
      package: package
    } do
      conn =
        build_conn()
        |> test_login(full_owner, sudo: false)
        |> post("/packages/#{package.name}/owners", %{"username" => non_owner.username})

      assert redirected_to(conn) =~ "/sudo"
    end

    test "shows error flash for unknown user", %{full_owner: full_owner, package: package} do
      conn =
        build_conn()
        |> test_login(full_owner, sudo: true)
        |> post("/packages/#{package.name}/owners", %{"username" => "nobody_exists_here"})

      assert redirected_to(conn) == "/packages/#{package.name}/owners"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "not found"
    end

    test "is forbidden for maintainer even with sudo", %{
      maintainer: maintainer,
      non_owner: non_owner,
      package: package
    } do
      conn =
        build_conn()
        |> test_login(maintainer, sudo: true)
        |> post("/packages/#{package.name}/owners", %{"username" => non_owner.username})

      assert conn.status == 403
    end

    test "shows error when re-adding the last full owner with lower level", %{
      full_owner: full_owner,
      package: package
    } do
      conn =
        build_conn()
        |> test_login(full_owner, sudo: true)
        |> post("/packages/#{package.name}/owners", %{
          "username" => full_owner.username,
          "level" => "maintainer"
        })

      assert redirected_to(conn) == "/packages/#{package.name}/owners"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "last full owner"
      assert Owners.get(package, full_owner).level == "full"
    end
  end

  describe "PUT /packages/:name/owners/:username (role change)" do
    test "full owner with sudo changes role", %{
      full_owner: full_owner,
      maintainer: maintainer,
      package: package
    } do
      conn =
        build_conn()
        |> test_login(full_owner, sudo: true)
        |> put("/packages/#{package.name}/owners/#{maintainer.username}", %{"level" => "full"})

      assert redirected_to(conn) == "/packages/#{package.name}/owners"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "full"
      updated_owner = Owners.get(package, maintainer)
      assert updated_owner.level == "full"
    end

    test "redirects to /sudo when no sudo mode", %{
      full_owner: full_owner,
      maintainer: maintainer,
      package: package
    } do
      conn =
        build_conn()
        |> test_login(full_owner, sudo: false)
        |> put("/packages/#{package.name}/owners/#{maintainer.username}", %{"level" => "full"})

      assert redirected_to(conn) =~ "/sudo"
    end

    test "cannot demote the last full owner", %{full_owner: full_owner, package: package} do
      conn =
        build_conn()
        |> test_login(full_owner, sudo: true)
        |> put("/packages/#{package.name}/owners/#{full_owner.username}", %{
          "level" => "maintainer"
        })

      assert redirected_to(conn) == "/packages/#{package.name}/owners"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "last full owner"
      # Confirm full_owner is still full
      assert Owners.get(package, full_owner).level == "full"
    end

    test "can demote a full owner when another full owner exists", %{package: package} do
      second_full = insert(:user)

      insert(:package_owner, package: package, user: second_full, level: "full")

      full_owner = insert(:user)
      insert(:package_owner, package: package, user: full_owner, level: "full")

      conn =
        build_conn()
        |> test_login(second_full, sudo: true)
        |> put("/packages/#{package.name}/owners/#{full_owner.username}", %{
          "level" => "maintainer"
        })

      assert redirected_to(conn) == "/packages/#{package.name}/owners"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "maintainer"
      assert Owners.get(package, full_owner).level == "maintainer"
    end

    test "self-demote redirects to package page", %{package: package} do
      second_full = insert(:user)
      insert(:package_owner, package: package, user: second_full, level: "full")

      conn =
        build_conn()
        |> test_login(second_full, sudo: true)
        |> put("/packages/#{package.name}/owners/#{second_full.username}", %{
          "level" => "maintainer"
        })

      assert redirected_to(conn) == "/packages/#{package.name}"
      assert Owners.get(package, second_full).level == "maintainer"
    end

    test "is forbidden for maintainer even with sudo", %{
      maintainer: maintainer,
      full_owner: full_owner,
      package: package
    } do
      conn =
        build_conn()
        |> test_login(maintainer, sudo: true)
        |> put("/packages/#{package.name}/owners/#{full_owner.username}", %{
          "level" => "maintainer"
        })

      assert conn.status == 403
    end
  end

  describe "DELETE /packages/:name/owners/:username" do
    test "full owner with sudo removes user", %{
      full_owner: full_owner,
      maintainer: maintainer,
      package: package
    } do
      conn =
        build_conn()
        |> test_login(full_owner, sudo: true)
        |> delete("/packages/#{package.name}/owners/#{maintainer.username}")

      assert redirected_to(conn) == "/packages/#{package.name}/owners"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "removed"
      assert is_nil(Owners.get(package, maintainer))
    end

    test "cannot remove the last owner", _context do
      sole_owner = insert(:user)

      sole_package =
        insert(:package, package_owners: [build(:package_owner, user: sole_owner, level: "full")])

      sole_package = Hexpm.Repo.preload(sole_package, :repository)

      conn =
        build_conn()
        |> test_login(sole_owner, sudo: true)
        |> delete("/packages/#{sole_package.name}/owners/#{sole_owner.username}")

      assert redirected_to(conn) == "/packages/#{sole_package.name}/owners"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "last owner"
    end

    test "cannot remove the last full owner when only maintainers remain", %{
      full_owner: full_owner,
      package: package
    } do
      conn =
        build_conn()
        |> test_login(full_owner, sudo: true)
        |> delete("/packages/#{package.name}/owners/#{full_owner.username}")

      assert redirected_to(conn) == "/packages/#{package.name}/owners"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "last full owner"
      assert Owners.get(package, full_owner)
    end

    test "self-removal redirects to package page", %{package: package} do
      second_full = insert(:user)
      insert(:package_owner, package: package, user: second_full, level: "full")

      conn =
        build_conn()
        |> test_login(second_full, sudo: true)
        |> delete("/packages/#{package.name}/owners/#{second_full.username}")

      assert redirected_to(conn) == "/packages/#{package.name}"
      assert is_nil(Owners.get(package, second_full))
    end

    test "redirects to /sudo when no sudo mode", %{
      full_owner: full_owner,
      maintainer: maintainer,
      package: package
    } do
      conn =
        build_conn()
        |> test_login(full_owner, sudo: false)
        |> delete("/packages/#{package.name}/owners/#{maintainer.username}")

      assert redirected_to(conn) =~ "/sudo"
    end
  end

  describe "private repository routes" do
    setup do
      org_user = insert(:user)
      organization = insert(:organization, user: org_user)
      repository = insert(:repository, organization: organization)

      full_owner = insert(:user)
      insert(:organization_user, organization: organization, user: full_owner, role: "admin")

      package =
        insert(:package,
          repository_id: repository.id,
          package_owners: [build(:package_owner, user: full_owner, level: "full")]
        )

      package = Hexpm.Repo.preload(package, :repository)

      %{
        repository: repository,
        full_owner: full_owner,
        package: package
      }
    end

    test "full owner can view management page on private repo", %{
      repository: repository,
      full_owner: full_owner,
      package: package
    } do
      conn =
        build_conn()
        |> test_login(full_owner)
        |> get("/packages/#{repository.name}/#{package.name}/owners")

      assert html_response(conn, 200) =~ "Current owners"
    end
  end
end
