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

  test "returns 404 for a user whose primary email is unverified" do
    user = insert(:user, full_name: "Unverified Person", emails: [build(:email, verified: false)])

    conn = get(build_conn(), "/users/#{user.username}")
    assert response(conn, 404)
    refute conn.resp_body =~ "Unverified Person"

    conn = get(build_conn(), "/users/#{user.username}/stats")
    assert response(conn, 404)
  end

  test "shows an organization page without any organization emails" do
    name = Hexpm.Fake.sequence(:package)
    insert(:organization, name: name, user: build(:user, username: name, emails: []))

    conn = get(build_conn(), "/orgs/#{name}")
    assert response(conn, 200) =~ name
  end

  describe "organization members tab" do
    test "lists only the members who chose to be shown" do
      organization = insert(:organization)
      shown = insert(:user)
      hidden = insert(:user)
      insert(:organization_user, organization: organization, user: shown, public: true)
      insert(:organization_user, organization: organization, user: hidden)

      html = build_conn() |> get("/orgs/#{organization.name}/members") |> html_response(200)

      assert html =~ ~s(id="organization-members")
      assert html =~ ~s(href="/users/#{shown.username}")
      refute html =~ ~s(href="/users/#{hidden.username}")
    end

    test "sits between Packages and Stats on an organization's profile" do
      organization = insert(:organization)

      for path <- ["/orgs/#{organization.name}", "/users/#{organization.name}/stats"] do
        html = build_conn() |> get(path) |> html_response(200)

        tabs =
          html
          |> LazyHTML.from_document()
          |> LazyHTML.query("#profile-tabs a")
          |> Enum.map(&LazyHTML.text/1)
          |> Enum.map(&String.trim/1)

        assert tabs == ["Packages", "Members", "Stats"]
        assert html =~ ~s(href="/orgs/#{organization.name}/members")
      end
    end

    test "says nobody is listed when nobody chose to be shown" do
      organization = insert(:organization)
      member = insert(:user)
      insert(:organization_user, organization: organization, user: member)

      html = build_conn() |> get("/orgs/#{organization.name}/members") |> html_response(200)

      assert html =~ "No Listed Members"
      refute html =~ ~s(id="organization-members")
      refute html =~ ~s(href="/users/#{member.username}")
    end

    test "leaves out members whose own profile isn't public" do
      organization = insert(:organization)
      unverified = insert(:user, emails: [build(:email, verified: false)])
      deactivated = insert(:user, deactivated_at: DateTime.utc_now())
      insert(:organization_user, organization: organization, user: unverified, public: true)
      insert(:organization_user, organization: organization, user: deactivated, public: true)

      html = build_conn() |> get("/orgs/#{organization.name}/members") |> html_response(200)

      refute html =~ ~s(id="organization-members")
      refute html =~ ~s(href="/users/#{unverified.username}")
      refute html =~ ~s(href="/users/#{deactivated.username}")
    end

    test "a user's profile has no members tab", c do
      html = build_conn() |> get("/users/#{c.user1.username}") |> html_response(200)
      refute html =~ ~s(/members")

      conn = get(build_conn(), "/orgs/#{c.user1.username}/members")
      assert response(conn, 404)
    end
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
