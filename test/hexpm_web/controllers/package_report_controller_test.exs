defmodule HexpmWeb.PackageReportControllerTest do
  use HexpmWeb.ConnCase, async: true

  setup do
    user1 = insert(:user) # Package 1 owner
    user2 = insert(:user, role: "moderator") # Pacakge 2 owner and mod
    user3 = insert(:user) # Report 1 author
    user4 = insert(:user) # No author, no mod, no owner

    repository1 = insert(:repository)
    repository2 = insert(:repository)

    owners = [build(:package_owner, user: user1)]
    package1 = insert(:package, name: "package1", package_owners: owners)

    package2 = insert(:package, owners: [user2])

    report1 = insert(
      :package_report,
      package: package1,
      author: user3,
      state: "to_accept",
      description: "report for first package"
    )

    report2 = insert(
      :package_report,
      package: package1,
      author: user3,
      state: "accepted",
      description: "report for first package"
    )

    report3 = insert(
      :package_report,
      package: package1,
      author: user3,
      state: "solved",
      description: "report for first package"
    )

    report4 = insert(
      :package_report,
      package: package1,
      author: user3,
      state: "rejected",
      description: "report for first package"
    )

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

    insert(:organization_user, user: user1, organization: repository1.organization)

    %{
      package1: package1,
      package2: package2,
      report1: report1,
      report2: report2,
      report3: report3,
      report4: report4,
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
      assert result =~ ~r/#{report1.id}/s
    end
  end

  describe "GET /reports/:id" do
    test "get invalid report", %{user1: user1} do
      conn = 
        build_conn()
        |> test_login(user1)
        |> get("/reports/1000")

      response(conn, 302)
    end

    test "get to_accept for author", %{user3: user3, report1: report1} do
      conn =
        build_conn()
        |> test_login(user3)
        |> get("/reports/#{report1.id}")
      
      result = response(conn, 200)
      assert result =~ "#{report1.id}"
      assert result =~ report1.package.name
      assert result =~ report1.description
      refute result =~ "comments" # Verify commnets section is not visible
    end

    test "get to_accept for moderator", %{user2: user2, report1: report1} do
      conn =
        build_conn()
        |> test_login(user2)
        |> get("/reports/#{report1.id}")
      
      result = response(conn, 200)
      assert result =~ "#{report1.id}"
      assert result =~ "#{report1.package.name}"
      assert result =~ "#{report1.description}"
      refute result =~ "comments" # Verify commnets section is not visible
    end

    test "get to_accept for owner", %{user1: user1, report1: report1} do
      conn =
        build_conn()
        |> test_login(user1)
        |> get("/reports/#{report1.id}")
      
      response(conn, 302)
    end

    test "get to_accept for others", %{user4: user4, report1: report1} do
      conn =
        build_conn()
        |> test_login(user4)
        |> get("/reports/#{report1.id}")
      
      response(conn, 302)
    end

    test "get rejected for author", %{user3: user3, report4: report4} do
      conn =
        build_conn()
        |> test_login(user3)
        |> get("/reports/#{report4.id}")
      
      result = response(conn, 200)
      assert result =~ "#{report4.id}"
      assert result =~ "#{report4.package.name}"
      assert result =~ "#{report4.description}"
      assert result =~ "comments" # Verify commnets section is not visible
    end

    test "get rejected for moderator", %{user2: user2, report4: report4} do
      conn =
        build_conn()
        |> test_login(user2)
        |> get("/reports/#{report4.id}")
      
      result = response(conn, 200)
      assert result =~ "#{report4.id}"
      assert result =~ "#{report4.package.name}"
      assert result =~ "#{report4.description}"
      assert result =~ "comments" # Verify commnets section is not visible
    end

    test "get rejected for owner", %{user1: user1, report4: report4} do
      conn =
        build_conn()
        |> test_login(user1)
        |> get("/reports/#{report4.id}")
      
      response(conn, 302)
    end

    test "get rejected for others", %{user4: user4, report4: report4} do
      conn =
        build_conn()
        |> test_login(user4)
        |> get("/reports/#{report4.id}")
      
      response(conn, 302)
    end

    test "get accepted for author", %{user3: user3, report2: report2} do
      conn =
        build_conn()
        |> test_login(user3)
        |> get("/reports/#{report2.id}")
      
      result = response(conn, 200)
      assert result =~ "#{report2.id}"
      assert result =~ "#{report2.package.name}"
      assert result =~ "#{report2.description}"
      assert result =~ "comments" # Verify commnets section is visible
    end

    test "get accepted for moderator", %{user2: user2, report2: report2} do
      conn =
        build_conn()
        |> test_login(user2)
        |> get("/reports/#{report2.id}")
      
      result = response(conn, 200)
      assert result =~ "#{report2.id}"
      assert result =~ "#{report2.package.name}"
      assert result =~ "#{report2.description}"
      assert result =~ "comments" # Verify commnets section is visible
    end

    test "get accepted for owner", %{user1: user1, report2: report2} do
      conn =
        build_conn()
        |> test_login(user1)
        |> get("/reports/#{report2.id}")
      
      result = response(conn, 200)
      assert result =~ "#{report2.id}"
      assert result =~ "#{report2.package.name}"
      assert result =~ "#{report2.description}"
      assert result =~ "comments" # Verify commnets section is visible
    end

    test "get accepted for others", %{user4: user4, report2: report2} do
      conn =
        build_conn()
        |> test_login(user4)
        |> get("/reports/#{report2.id}")
      response(conn, 302)
    end

    test "get solved for author", %{user3: user3, report3: report3} do
      conn =
        build_conn()
        |> test_login(user3)
        |> get("/reports/#{report3.id}")
      
      result = response(conn, 200)
      assert result =~ "#{report3.id}"
      assert result =~ "#{report3.package.name}"
      assert result =~ "#{report3.description}"
      assert result =~ "comments" # Verify commnets section is visible
    end

    test "get solved for moderator", %{user2: user2, report3: report3} do
      conn =
        build_conn()
        |> test_login(user2)
        |> get("/reports/#{report3.id}")
      
      result = response(conn, 200)
      assert result =~ "#{report3.id}"
      assert result =~ "#{report3.package.name}"
      assert result =~ "#{report3.description}"
      assert result =~ "comments" # Verify commnets section is visible
    end

    test "get solved for owner", %{user1: user1, report3: report3} do
      conn =
        build_conn()
        |> test_login(user1)
        |> get("/reports/#{report3.id}")
      
      result = response(conn, 200)
      assert result =~ "#{report3.id}"
      assert result =~ "#{report3.package.name}"
      assert result =~ "#{report3.description}"
      assert result =~ "comments" # Verify commnets section is visible
    end

    test "get solved for others", %{user4: user4, report3: report3} do
      conn =
        build_conn()
        |> test_login(user4)
        |> get("/reports/#{report3.id}")
      
      result = response(conn, 200)
      assert result =~ "#{report3.id}"
      assert result =~ "#{report3.package.name}"
      assert result =~ "#{report3.description}"
      refute result =~ "comments" # Verify commnets section is not visible
    end
  end
end
