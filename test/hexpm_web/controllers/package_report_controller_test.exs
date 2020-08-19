defmodule HexpmWeb.PackageReportControllerTest do
  use HexpmWeb.ConnCase, async: true

  setup do
    # Package 1 owner
    user1 = insert(:user)
    # Pacakge 2 owner and mod
    user2 = insert(:user, role: "moderator")
    # Report 1 author
    user3 = insert(:user)
    # No author, no mod, no owner
    user4 = insert(:user)

    repository1 = insert(:repository)
    repository2 = insert(:repository)

    owners = [build(:package_owner, user: user1)]
    package1 = insert(:package, name: "package1", package_owners: owners)

    package2 = insert(:package, owners: [user2])

    release1 =
      insert(
        :release,
        package: package1,
        version: "0.0.1",
        meta: build(:release_metadata, app: package1.name)
      )

    release2 =
      insert(
        :release,
        package: package1,
        version: "0.0.2",
        meta: build(:release_metadata, app: package1.name)
      )

    insert(:organization_user, user: user1, organization: repository1.organization)

    report1 =
      insert(
        :package_report,
        package: package1,
        author: user3,
        state: "to_accept",
        description: "report for first package"
      )

    insert(:package_report_release, release: release1, package_report: report1)

    report2 =
      insert(
        :package_report,
        package: package1,
        author: user3,
        state: "accepted",
        description: "report for first package"
      )
    
    insert(:package_report_release, release: release1, package_report: report2)

    report3 =
      insert(
        :package_report,
        package: package1,
        author: user3,
        state: "solved",
        description: "report for first package"
      )

    report4 =
      insert(
        :package_report,
        package: package1,
        author: user3,
        state: "rejected",
        description: "report for first package"
      )

    report5 =
      insert(
        :package_report,
        package: package1,
        author: user3,
        state: "unresolved",
        description: "report for first package"
      )

    %{
      package1: package1,
      package2: package2,
      report1: report1,
      report2: report2,
      report3: report3,
      report4: report4,
      report5: report5,
      release1: release1,
      repository1: repository1,
      repository2: repository2,
      user1: user1,
      user2: user2,
      user3: user3,
      user4: user4
    }
  end

  describe "GET /reports" do
    test "list all", %{user1: user1, report1: report1} do
      conn =
        build_conn()
        |> test_login(user1)
        |> get("/reports")

      result = response(conn, 200)
      assert result =~ "#{report1.id}<\/a><\/td>"
    end
  end

  describe "GET /reports/:id" do
    test "get invalid report", %{user1: user1} do
      conn =
        build_conn()
        |> test_login(user1)
        |> get("/reports/1000")

      response(conn, 404)
    end

    test "get to_accept for author", %{user3: user3, report1: report1} do
      conn =
        build_conn()
        |> test_login(user3)
        |> get("/reports/#{report1.id}")

      result = response(conn, 200)
      assert result =~ "id #{report1.id}<\/p>"
      assert result =~ "on #{report1.package.name} package<\/p>"
      assert result =~ "<p>#{report1.description}<\/p>"
      # Verify commets section is not visible
      refute result =~ "comments-section-div"
    end

    test "get to_accept for moderator", %{user2: user2, report1: report1} do
      conn =
        build_conn()
        |> test_login(user2)
        |> get("/reports/#{report1.id}")

      result = response(conn, 200)
      assert result =~ "id #{report1.id}<\/p>"
      assert result =~ "on #{report1.package.name} package<\/p>"
      assert result =~ "<p>#{report1.description}<\/p>"
      # Verify commnets section is not visible
      refute result =~ "comments-section-div"
    end

    test "get to_accept for owner", %{user1: user1, report1: report1} do
      conn =
        build_conn()
        |> test_login(user1)
        |> get("/reports/#{report1.id}")

      response(conn, 404)
    end

    test "get to_accept for others", %{user4: user4, report1: report1} do
      conn =
        build_conn()
        |> test_login(user4)
        |> get("/reports/#{report1.id}")

      response(conn, 404)
    end

    test "get rejected for author", %{user3: user3, report4: report4} do
      conn =
        build_conn()
        |> test_login(user3)
        |> get("/reports/#{report4.id}")

      result = response(conn, 200)
      assert result =~ "id #{report4.id}<\/p>"
      assert result =~ "on #{report4.package.name} package<\/p>"
      assert result =~ "<p>#{report4.description}<\/p>"
      # Verify commnets section is not visible
      assert result =~ "comments-section-div"
    end

    test "get rejected for moderator", %{user2: user2, report4: report4} do
      conn =
        build_conn()
        |> test_login(user2)
        |> get("/reports/#{report4.id}")

      result = response(conn, 200)
      assert result =~ "id #{report4.id}<\/p>"
      assert result =~ "on #{report4.package.name} package<\/p>"
      assert result =~ "<p>#{report4.description}<\/p>"
      # Verify commnets section is not visible
      assert result =~ "comments-section-div"
    end

    test "get rejected for owner", %{user1: user1, report4: report4} do
      conn =
        build_conn()
        |> test_login(user1)
        |> get("/reports/#{report4.id}")

      response(conn, 404)
    end

    test "get rejected for others", %{user4: user4, report4: report4} do
      conn =
        build_conn()
        |> test_login(user4)
        |> get("/reports/#{report4.id}")

      response(conn, 404)
    end

    test "get accepted for author", %{user3: user3, report2: report2} do
      conn =
        build_conn()
        |> test_login(user3)
        |> get("/reports/#{report2.id}")

      result = response(conn, 200)
      assert result =~ "id #{report2.id}<\/p>"
      assert result =~ "on #{report2.package.name} package<\/p>"
      assert result =~ "<p>#{report2.description}<\/p>"
      # Verify commnets section is visible
      assert result =~ "comments-section-div"
    end

    test "get accepted for moderator", %{user2: user2, report2: report2} do
      conn =
        build_conn()
        |> test_login(user2)
        |> get("/reports/#{report2.id}")

      result = response(conn, 200)
      assert result =~ "id #{report2.id}<\/p>"
      assert result =~ "on #{report2.package.name} package<\/p>"
      assert result =~ "<p>#{report2.description}<\/p>"
      # Verify commnets section is visible
      assert result =~ "comments-section-div"
    end

    test "get accepted for owner", %{user1: user1, report2: report2} do
      conn =
        build_conn()
        |> test_login(user1)
        |> get("/reports/#{report2.id}")

      result = response(conn, 200)
      assert result =~ "id #{report2.id}<\/p>"
      assert result =~ "on #{report2.package.name} package<\/p>"
      assert result =~ "<p>#{report2.description}<\/p>"
      # Verify commnets section is visible
      assert result =~ "comments-section-div"
    end

    test "get accepted for others", %{user4: user4, report2: report2} do
      conn =
        build_conn()
        |> test_login(user4)
        |> get("/reports/#{report2.id}")

      response(conn, 404)
    end

    test "get solved for author", %{user3: user3, report3: report3} do
      conn =
        build_conn()
        |> test_login(user3)
        |> get("/reports/#{report3.id}")

      result = response(conn, 200)
      assert result =~ "id #{report3.id}<\/p>"
      assert result =~ "on #{report3.package.name} package<\/p>"
      assert result =~ "<p>#{report3.description}<\/p>"
      # Verify commnets section is visible
      assert result =~ "comments-section-div"
    end

    test "get solved for moderator", %{user2: user2, report3: report3} do
      conn =
        build_conn()
        |> test_login(user2)
        |> get("/reports/#{report3.id}")

      result = response(conn, 200)
      assert result =~ "id #{report3.id}<\/p>"
      assert result =~ "on #{report3.package.name} package<\/p>"
      assert result =~ "<p>#{report3.description}<\/p>"
      # Verify commnets section is visible
      assert result =~ "comments-section-div"
    end

    test "get solved for owner", %{user1: user1, report3: report3} do
      conn =
        build_conn()
        |> test_login(user1)
        |> get("/reports/#{report3.id}")

      result = response(conn, 200)
      assert result =~ "id #{report3.id}<\/p>"
      assert result =~ "on #{report3.package.name} package<\/p>"
      assert result =~ "<p>#{report3.description}<\/p>"
      # Verify commnets section is visible
      assert result =~ "comments-section-div"
    end

    test "get solved for others", %{user4: user4, report3: report3} do
      conn =
        build_conn()
        |> test_login(user4)
        |> get("/reports/#{report3.id}")

      result = response(conn, 200)
      assert result =~ "id #{report3.id}<\/p>"
      assert result =~ "on #{report3.package.name} package<\/p>"
      assert result =~ "<p>#{report3.description}<\/p>"
      # Verify commnets section is not visible
      refute result =~ "comments-section-div"
    end

    test "get unresolved for author", %{user3: user3, report5: report5} do
      conn =
        build_conn()
        |> test_login(user3)
        |> get("/reports/#{report5.id}")

      result = response(conn, 200)
      assert result =~ "id #{report5.id}<\/p>"
      assert result =~ "on #{report5.package.name} package<\/p>"
      assert result =~ "<p>#{report5.description}<\/p>"
      # Verify commnets section is visible
      assert result =~ "comments-section-div"
    end

    test "get unresolved for moderator", %{user2: user2, report5: report5} do
      conn =
        build_conn()
        |> test_login(user2)
        |> get("/reports/#{report5.id}")

      result = response(conn, 200)
      assert result =~ "id #{report5.id}<\/p>"
      assert result =~ "on #{report5.package.name} package<\/p>"
      assert result =~ "<p>#{report5.description}<\/p>"
      # Verify commnets section is visible
      assert result =~ "comments-section-div"
    end

    test "get unresolved for owner", %{user1: user1, report5: report5} do
      conn =
        build_conn()
        |> test_login(user1)
        |> get("/reports/#{report5.id}")

      result = response(conn, 200)
      assert result =~ "id #{report5.id}<\/p>"
      assert result =~ "on #{report5.package.name} package<\/p>"
      assert result =~ "<p>#{report5.description}<\/p>"
      # Verify commnets section is visible
      assert result =~ "comments-section-div"
    end

    test "get unresolved for others", %{user4: user4, report5: report5} do
      conn =
        build_conn()
        |> test_login(user4)
        |> get("/reports/#{report5.id}")

      result = response(conn, 200)
      assert result =~ "id #{report5.id}<\/p>"
      assert result =~ "on #{report5.package.name} package<\/p>"
      assert result =~ "<p>#{report5.description}<\/p>"
      # Verify commnets section is not visible
      refute result =~ "comments-section-div"
    end
  end

  describe "solve/2" do
    test "get marked package after solve report", %{
      report2: report2,
      package1: package1,
      user2: user2,
      release1: release1
    } do
      conn =
        build_conn()
        |> test_login(user2)
        |> post("/reports/#{report2.id}/solve")

      result = response(conn, 302)

      conn1 =
        build_conn()
        |> test_login(user2)
        |> get("/packages/#{package1.name}")

      result = response(conn1, 200)

      assert result =~ "<h2 class=\"package-title\">#{package1.name}"
      assert result =~ "<strong>#{release1.version}</strong>"
      assert result =~ "(<span class=\"version-retirement\">reported</span>)"
    end
  end
end
