defmodule HexpmWeb.API.UserControllerTest do
  use HexpmWeb.ConnCase, async: true

  alias Hexpm.Accounts.User

  describe "GET /api/users/me" do
    test "get current user" do
      user = insert(:user)
      repository = insert(:repository)
      package1 = insert(:package, package_owners: [build(:package_owner, user: user)])

      package2 =
        insert(
          :package,
          repository_id: repository.id,
          package_owners: [build(:package_owner, user: user)]
        )

      insert(:organization_user, organization: repository.organization, user: user)

      body =
        build_conn()
        |> put_req_header("authorization", key_for(user))
        |> get("/api/users/me")
        |> json_response(200)

      assert body["username"] == user.username
      assert body["email"] == hd(user.emails).email
      refute body["emails"]
      refute body["password"]
      assert hd(body["organizations"])["name"] == repository.organization.name
      assert hd(body["organizations"])["role"] == "read"

      assert [json1, json2] = body["packages"]
      assert json1["url"] =~ "/api/packages/#{package1.name}"
      assert json1["html_url"] =~ "/packages/#{package1.name}"
      assert json1["repository"] =~ "hexpm"
      assert json2["url"] =~ "/api/repos/#{repository.name}/packages/#{package2.name}"
      assert json2["html_url"] =~ "/packages/#{repository.name}/#{package2.name}"
      assert json2["repository"] =~ repository.name

      # TODO: deprecated
      assert Enum.count(body["owned_packages"]) == 2
      assert body["owned_packages"][package1.name] =~ "/api/packages/#{package1.name}"

      assert body["owned_packages"][package2.name] =~
               "/api/repos/#{repository.name}/packages/#{package2.name}"
    end

    test "return 401 if not authenticated" do
      build_conn()
      |> get("/api/users/me")
      |> json_response(401)
    end

    test "sorts organizations by name" do
      user = insert(:user)
      zulu = insert(:organization, name: "zulu_org")
      alpha = insert(:organization, name: "alpha_org")
      insert(:organization_user, organization: zulu, user: user)
      insert(:organization_user, organization: alpha, user: user)

      organizations =
        build_conn()
        |> put_req_header("authorization", key_for(user))
        |> get("/api/users/me")
        |> json_response(200)
        |> Map.fetch!("organizations")

      assert Enum.map(organizations, & &1["name"]) == ["alpha_org", "zulu_org"]
    end

    test "return 404 for organization keys" do
      organization = insert(:organization)

      build_conn()
      |> put_req_header("authorization", key_for(organization))
      |> get("/api/users/me")
      |> json_response(404)
    end
  end

  describe "GET /api/users/me/audit-logs" do
    test "returns audit_logs created by this current user" do
      user = insert(:user)
      insert(:audit_log, user: user, action: "test.user")

      assert [%{"action" => "test.user"}] =
               build_conn()
               |> put_req_header("authorization", key_for(user))
               |> get("/api/users/me/audit-logs")
               |> json_response(200)
    end

    test "returns 401 if not authenticated" do
      build_conn()
      |> get("/api/users/me/audit-logs")
      |> json_response(401)
    end

    test "returns 404 for organization keys" do
      organization = insert(:organization)

      build_conn()
      |> put_req_header("authorization", key_for(organization))
      |> get("/api/users/me/audit-logs")
      |> json_response(404)
    end
  end

  describe "GET /api/users/:name" do
    setup do
      user1 = insert(:user)
      user2 = insert(:user)
      user3 = insert(:user)

      repository1 = insert(:repository)
      repository2 = insert(:repository)
      insert(:organization_user, user: user1, organization: repository1.organization)
      insert(:organization_user, user: user2, organization: repository1.organization)
      insert(:organization_user, user: user3, organization: repository2.organization)

      # public package
      package1 = insert(:package, package_owners: [build(:package_owner, user: user1)])

      # private package
      package2 =
        insert(
          :package,
          repository_id: repository1.id,
          package_owners: [build(:package_owner, user: user1)]
        )

      %{
        user1: user1,
        user2: user2,
        user3: user3,
        package1: package1,
        package2: package2
      }
    end

    test "get user" do
      user = insert(:user)
      conn = get(build_conn(), "/api/users/#{user.username}")

      body = json_response(conn, 200)
      assert body["username"] == user.username
      assert body["email"] == hd(user.emails).email
      refute body["emails"]
      refute body["password"]

      conn = get(build_conn(), "/api/users/bad")
      assert conn.status == 404
    end

    test "returns 404 for a user whose primary email is unverified" do
      user = insert(:user, emails: [build(:email, verified: false)])

      conn = get(build_conn(), "/api/users/#{user.username}")
      assert conn.status == 404
      refute conn.resp_body =~ hd(user.emails).email
    end

    test "returns an organization account without any organization emails" do
      name = Hexpm.Fake.sequence(:package)
      insert(:organization, name: name, user: build(:user, username: name, emails: []))

      body =
        build_conn()
        |> get("/api/users/#{name}")
        |> json_response(200)

      assert body["username"] == name
      refute body["email"]
    end

    test "show owned packages as owner", data do
      conn =
        build_conn()
        |> put_req_header("authorization", key_for(data.user1))
        |> get("/api/users/#{data.user1.username}")

      both = Enum.sort([data.package1.name, data.package2.name])
      assert listed_packages(conn) == {both, both}
    end

    test "show owned packages as user from the same organization", data do
      conn =
        build_conn()
        |> put_req_header("authorization", key_for(data.user2))
        |> get("/api/users/#{data.user1.username}")

      both = Enum.sort([data.package1.name, data.package2.name])
      assert listed_packages(conn) == {both, both}
    end

    test "show owned packages as other user", data do
      conn =
        build_conn()
        |> put_req_header("authorization", key_for(data.user3))
        |> get("/api/users/#{data.user1.username}")

      assert listed_packages(conn) == {[data.package1.name], [data.package1.name]}
    end
  end

  describe "POST /api/users/:name/reset" do
    test "password reset endpoint is not available" do
      user = insert(:user)

      conn = post(build_conn(), "/api/users/#{user.username}/reset", %{})
      assert conn.status == 404

      user =
        Hexpm.Repo.get_by!(User, username: user.username)
        |> Hexpm.Repo.preload([:emails, :password_resets])

      assert user.password_resets == []
    end
  end

  describe "GET /api/users/:name/test" do
    test "test auth" do
      user = insert(:user)

      conn =
        build_conn()
        |> put_req_header("authorization", key_for(user))
        |> get("/api/users/#{user.username}/test")

      body = json_response(conn, 200)
      assert body["username"] == user.username

      conn =
        build_conn()
        |> put_req_header("authorization", "badkey")
        |> get("/api/users/#{user.username}/test")

      assert conn.status == 401
    end
  end

  # Matching names against the raw body makes any package name that happens to
  # be a substring of a username, an email or another name a false result. A
  # generated username of "xenolinguist" against a package called "linguist" is
  # what turned this red on CI.
  defp listed_packages(conn) do
    body = json_response(conn, 200)

    {
      body |> Map.fetch!("packages") |> Enum.map(& &1["name"]) |> Enum.sort(),
      body |> Map.fetch!("owned_packages") |> Map.keys() |> Enum.sort()
    }
  end
end
