defmodule HexpmWeb.UserControllerTest do
  use HexpmWeb.ConnCase, async: true

  setup do
    user1 = insert(:user)
    user2 = insert(:user)
    user3 = insert(:user)

    repository1 = insert(:repository)
    repository2 = insert(:repository)

    owners = [build(:package_owner, user: user1)]

    package1 =
      insert(:package, name: "package1", package_owners: owners, releases: [build(:release)])

    package2 =
      insert(
        :package,
        name: "package2",
        package_owners: owners,
        repository_id: repository1.id,
        releases: [build(:release)]
      )

    insert(:package, name: "package3", repository_id: repository2.id)

    insert(:organization_user, user: user1, organization: repository1.organization)
    insert(:organization_user, user: user2, organization: repository1.organization)

    %{
      package1: package1,
      package2: package2,
      user1: user1,
      user2: user2,
      user3: user3
    }
  end

  test "show profile page", c do
    conn =
      build_conn()
      |> test_login(c.user1)
      |> get("/users/#{c.user1.username}")

    assert response(conn, 200) =~ c.user1.username
  end

  test "show owned packages as owner", c do
    conn =
      build_conn()
      |> test_login(c.user1)
      |> get("/users/#{c.user1.username}")

    assert response(conn, 200) =~ c.package1.name
    assert response(conn, 200) =~ c.package2.name
  end

  test "show owned packages as user from the same organization", c do
    conn =
      build_conn()
      |> test_login(c.user2)
      |> get("/users/#{c.user1.username}")

    assert response(conn, 200) =~ c.package1.name
    assert response(conn, 200) =~ c.package2.name
  end

  test "show owned packages as other user", c do
    conn =
      build_conn()
      |> test_login(c.user3)
      |> get("/users/#{c.user1.username}")

    assert response(conn, 200) =~ c.package1.name
    refute response(conn, 200) =~ c.package2.name
  end

  describe "stats page" do
    test "renders for the owner", c do
      conn =
        build_conn()
        |> test_login(c.user1)
        |> get("/users/#{c.user1.username}/stats")

      assert response(conn, 200) =~ "Stats"
      assert response(conn, 200) =~ c.package1.name
      assert response(conn, 200) =~ c.package2.name
    end

    test "renders for another authenticated user", c do
      conn =
        build_conn()
        |> test_login(c.user3)
        |> get("/users/#{c.user1.username}/stats")

      assert response(conn, 200) =~ "Stats"
      assert response(conn, 200) =~ c.package1.name
      refute response(conn, 200) =~ c.package2.name
    end

    test "renders without authentication", c do
      conn =
        build_conn()
        |> get("/users/#{c.user1.username}/stats")

      assert response(conn, 200) =~ "Stats"
      assert response(conn, 200) =~ c.package1.name
      refute response(conn, 200) =~ c.package2.name
    end

    test "returns 404 for unknown user", _c do
      conn =
        build_conn()
        |> get("/users/unknown_xyz_user/stats")

      assert response(conn, 404)
    end

    test "renders for user from same organization", c do
      conn =
        build_conn()
        |> test_login(c.user2)
        |> get("/users/#{c.user1.username}/stats")

      assert response(conn, 200) =~ "Stats"
      assert response(conn, 200) =~ c.package1.name
      assert response(conn, 200) =~ c.package2.name
    end

    test "sort=name renders packages in alphabetical order", c do
      conn =
        build_conn()
        |> test_login(c.user1)
        |> get("/users/#{c.user1.username}/stats?sort=name")

      html = response(conn, 200)
      assert html =~ "Stats"
      # package1 < package2 alphabetically, so package1 should appear first
      assert :binary.match(html, c.package1.name) < :binary.match(html, c.package2.name)
    end

    test "sort=downloads is the default and renders successfully", c do
      conn =
        build_conn()
        |> test_login(c.user1)
        |> get("/users/#{c.user1.username}/stats?sort=downloads")

      assert response(conn, 200) =~ "Stats"
    end

    test "unknown sort param falls back gracefully", c do
      conn =
        build_conn()
        |> test_login(c.user1)
        |> get("/users/#{c.user1.username}/stats?sort=invalid")

      assert response(conn, 200) =~ "Stats"
      assert response(conn, 200) =~ c.package1.name
    end
  end
end
