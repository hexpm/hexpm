defmodule HexpmWeb.VersionControllerTest do
  use HexpmWeb.ConnCase, async: true

  setup do
    user1 = insert(:user)

    organization1 = insert(:organization)

    package1 = insert(:package)
    package2 = insert(:package, organization_id: organization1.id)

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

    insert(:organization_user, user: user1, organization: organization1)

    %{
      package1: package1,
      package2: package2,
      organization1: organization1,
      user1: user1
    }
  end

  describe "GET /packages/:package_name/versions" do
    test "list all versions for public package", %{package1: package1} do
      conn = get(build_conn(), "/packages/#{package1.name}/versions")
      result = response(conn, 200)
      assert result =~ ~r/0.0.1/
      assert result =~ ~r/0.0.2/
      assert result =~ ~r/0.0.3-dev/
      assert result =~ package1.name
    end

    test "list private package versions", %{
      user1: user1,
      package2: package2,
      organization1: organization1
    } do
      conn =
        build_conn()
        |> test_login(user1)
        |> get("/packages/#{organization1.name}/#{package2.name}/versions")

      result = response(conn, 200)
      assert result =~ ~r/0.1.0/
      assert result =~ ~r/1.0.0/
      assert result =~ package2.name
    end
  end
end
