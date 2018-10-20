defmodule HexpmWeb.UserControllerTest do
  use HexpmWeb.ConnCase, async: true

  setup do
    user1 = insert(:user)
    user2 = insert(:user)
    user3 = insert(:user)

    organization1 = insert(:organization)
    organization2 = insert(:organization)

    owners = [build(:package_owner, user: user1)]
    package1 = insert(:package, name: "package1", package_owners: owners)

    package2 =
      insert(
        :package,
        name: "package2",
        package_owners: owners,
        organization_id: organization1.id
      )

    package3 = insert(:package, name: "package3", organization_id: organization2.id)

    insert(:organization_user, user: user1, organization: organization1)
    insert(:organization_user, user: user2, organization: organization1)

    %{
      package1: package1,
      package2: package2,
      package3: package3,
      organization1: organization1,
      organization2: organization2,
      user1: user1,
      user2: user2,
      user3: user3
    }
  end

  test "show profile page", c do
    conn =
      build_conn()
      |> test_login(c.user1)
      |> get("users/#{c.user1.username}")

    assert response(conn, 200) =~ c.user1.username
  end

  test "show owned packages as owner", c do
    conn =
      build_conn()
      |> test_login(c.user1)
      |> get("users/#{c.user1.username}")

    assert response(conn, 200) =~ c.package1.name
    assert response(conn, 200) =~ c.package2.name
  end

  test "show owned packages as user from the same organization", c do
    conn =
      build_conn()
      |> test_login(c.user2)
      |> get("users/#{c.user1.username}")

    assert response(conn, 200) =~ c.package1.name
    assert response(conn, 200) =~ c.package2.name
  end

  test "show owned packages as other user", c do
    conn =
      build_conn()
      |> test_login(c.user3)
      |> get("users/#{c.user1.username}")

    assert response(conn, 200) =~ c.package1.name
    refute response(conn, 200) =~ c.package2.name
  end
end
