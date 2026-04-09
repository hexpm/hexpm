defmodule HexpmWeb.PackageVersionsControllerTest do
  use HexpmWeb.ConnCase, async: true

  setup do
    user1 = insert(:user)

    repository1 = insert(:repository)

    package1 = insert(:package)
    package2 = insert(:package, repository_id: repository1.id)

    insert(
      :release,
      package: package1,
      version: "0.0.1",
      meta: build(:release_metadata, app: package1.name)
    )

    insert(
      :release,
      package: package1,
      version: "0.0.2",
      meta: build(:release_metadata, app: package1.name)
    )

    insert(
      :release,
      package: package1,
      version: "0.0.3-dev",
      meta: build(:release_metadata, app: package1.name)
    )

    insert(
      :release,
      package: package2,
      version: "1.0.0",
      meta: build(:release_metadata, app: package2.name)
    )

    insert(
      :release,
      package: package2,
      version: "0.1.0",
      meta: build(:release_metadata, app: package2.name)
    )

    insert(:organization_user, user: user1, organization: repository1.organization)

    %{
      package1: package1,
      package2: package2,
      repository1: repository1,
      user1: user1
    }
  end

  describe "GET /packages/:package_name/versions" do
    test "list all versions for public package", %{package1: package1} do
      conn = get(build_conn(), "/packages/#{package1.name}/versions")
      result = response(conn, 200)
      assert result =~ "0.0.1"
      assert result =~ "0.0.2"
      assert result =~ "0.0.3-dev"
      assert result =~ package1.name
    end

    test "list private package versions", %{
      user1: user1,
      package2: package2,
      repository1: repository1
    } do
      conn =
        build_conn()
        |> test_login(user1)
        |> get("/packages/#{repository1.name}/#{package2.name}/versions")

      result = response(conn, 200)
      assert result =~ "0.1.0"
      assert result =~ "1.0.0"
      assert result =~ package2.name
    end

    test "unauthenticated access to private package versions returns 404", %{
      package2: package2,
      repository1: repository1
    } do
      conn = get(build_conn(), "/packages/#{repository1.name}/#{package2.name}/versions")
      assert response(conn, 404)
    end

    test "user without org access cannot view private package versions", %{
      package2: package2,
      repository1: repository1
    } do
      other_user = insert(:user)

      conn =
        build_conn()
        |> test_login(other_user)
        |> get("/packages/#{repository1.name}/#{package2.name}/versions")

      assert response(conn, 404)
    end
  end
end
