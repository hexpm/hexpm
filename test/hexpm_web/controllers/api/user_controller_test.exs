defmodule HexpmWeb.API.UserControllerTest do
  use HexpmWeb.ConnCase, async: true
  use Bamboo.Test

  alias Hexpm.Accounts.User

  defp publish_package(user) do
    meta = %{name: "ecto", version: "1.0.0", description: "Domain-specific language."}
    body = create_tar(meta)

    build_conn()
    |> put_req_header("content-type", "application/octet-stream")
    |> put_req_header("authorization", key_for(user))
    |> post("api/packages/ecto/releases", body)
  end

  describe "POST /api/users" do
    test "create user" do
      params = %{
        username: Fake.sequence(:username),
        email: Fake.sequence(:email),
        password: "passpass"
      }

      conn = json_post(build_conn(), "api/users", params)
      assert json_response(conn, 201)["url"] =~ "/api/users/#{params.username}"

      user = Hexpm.Repo.get_by!(User, username: params.username) |> Hexpm.Repo.preload(:emails)
      assert List.first(user.emails).email == params.email
    end

    test "create user sends mails and requires confirmation" do
      params = %{
        username: Fake.sequence(:username),
        email: Fake.sequence(:email),
        password: "passpass"
      }

      conn = json_post(build_conn(), "api/users", params)

      assert conn.status == 201
      user = Hexpm.Repo.get_by!(User, username: params.username) |> Hexpm.Repo.preload(:emails)
      user_email = List.first(user.emails)

      assert_delivered_email(Hexpm.Emails.verification(user, user_email))

      conn = publish_package(user)
      assert json_response(conn, 403)["message"] == "email not verified"

      conn =
        get(
          build_conn(),
          "email/verify",
          username: params.username,
          email: user_email.email,
          key: user_email.verification_key
        )

      assert redirected_to(conn) == "/"
      assert get_flash(conn, :info) =~ "verified"

      conn = publish_package(user)
      assert conn.status == 201
    end

    test "create user validates" do
      params = %{username: Fake.sequence(:username), password: "passpass"}
      conn = json_post(build_conn(), "api/users", params)

      result = json_response(conn, 422)
      assert result["message"] == "Validation error(s)"
      assert result["errors"]["emails"] == "can't be blank"
      refute Hexpm.Repo.get_by(User, username: params.username)
    end
  end

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
        |> get("api/users/me")
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
      |> get("api/users/me")
      |> json_response(401)
    end

    test "return 404 for organization keys" do
      organization = insert(:organization)

      build_conn()
      |> put_req_header("authorization", key_for(organization))
      |> get("api/users/me")
      |> json_response(404)
    end
  end

  describe "GET /api/users/me/audit_logs" do
    test "returns audit_logs created by this current user" do
      user = insert(:user)
      insert(:audit_log, user: user, action: "test.user")

      assert [%{"action" => "test.user"}] =
               build_conn()
               |> put_req_header("authorization", key_for(user))
               |> get("/api/users/me/audit_logs")
               |> json_response(200)
    end

    test "returns 401 if not authenticated" do
      build_conn()
      |> get("/api/users/me/audit_logs")
      |> json_response(401)
    end

    test "returns 404 for organization keys" do
      organization = insert(:organization)

      build_conn()
      |> put_req_header("authorization", key_for(organization))
      |> get("api/users/me/audit_logs")
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
      conn = get(build_conn(), "api/users/#{user.username}")

      body = json_response(conn, 200)
      assert body["username"] == user.username
      assert body["email"] == hd(user.emails).email
      refute body["emails"]
      refute body["password"]

      conn = get(build_conn(), "api/users/bad")
      assert conn.status == 404
    end

    test "show owned packages as owner", data do
      conn =
        build_conn()
        |> put_req_header("authorization", key_for(data.user1))
        |> get("api/users/#{data.user1.username}")

      assert response(conn, 200) =~ data.package1.name
      assert response(conn, 200) =~ data.package2.name
    end

    test "show owned packages as user from the same organization", data do
      conn =
        build_conn()
        |> put_req_header("authorization", key_for(data.user2))
        |> get("api/users/#{data.user1.username}")

      assert response(conn, 200) =~ data.package1.name
      assert response(conn, 200) =~ data.package2.name
    end

    test "show owned packages as other user", data do
      conn =
        build_conn()
        |> put_req_header("authorization", key_for(data.user3))
        |> get("api/users/#{data.user1.username}")

      assert response(conn, 200) =~ data.package1.name
      refute response(conn, 200) =~ data.package2.name
    end
  end

  describe "POST /api/users/:name/reset" do
    test "email is sent with reset_token when password is reset" do
      user = insert(:user)

      # initiate reset requests
      conn = post(build_conn(), "api/users/#{user.username}/reset", %{})
      assert conn.status == 204

      # initiate second reset request
      conn = post(build_conn(), "api/users/#{user.username}/reset", %{})
      assert conn.status == 204

      user =
        Hexpm.Repo.get_by!(User, username: user.username)
        |> Hexpm.Repo.preload([:emails, :password_resets])

      assert [reset1, reset2] = user.password_resets

      # check email was sent with correct token
      assert_delivered_email(Hexpm.Emails.password_reset_request(user, reset1))
      assert_delivered_email(Hexpm.Emails.password_reset_request(user, reset2))

      # check reset will succeed
      assert User.can_reset_password?(user, reset1.key)
      assert User.can_reset_password?(user, reset2.key)
    end
  end

  describe "GET /api/users/:name/test" do
    test "test auth" do
      user = insert(:user)

      conn =
        build_conn()
        |> put_req_header("authorization", key_for(user))
        |> get("api/users/#{user.username}/test")

      body = json_response(conn, 200)
      assert body["username"] == user.username

      conn =
        build_conn()
        |> put_req_header("authorization", "badkey")
        |> get("api/users/#{user.username}/test")

      assert conn.status == 401
    end
  end
end
