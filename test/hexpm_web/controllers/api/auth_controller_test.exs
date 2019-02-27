defmodule HexpmWeb.API.AuthControllerTest do
  use HexpmWeb.ConnCase, async: true

  setup do
    owned_org = insert(:organization)
    unowned_org = insert(:organization)
    user = insert(:user)
    insert(:organization_user, organization: owned_org, user: user)

    user_full_key =
      insert(
        :key,
        user: user,
        permissions: [
          build(:key_permission, domain: "api"),
          build(:key_permission, domain: "repository", resource: owned_org.name)
        ]
      )

    organization_full_key =
      insert(
        :key,
        organization: owned_org,
        permissions: [
          build(:key_permission, domain: "api"),
          build(:key_permission, domain: "repository", resource: owned_org.name)
        ]
      )

    user_api_key = insert(:key, user: user, permissions: [build(:key_permission, domain: "api")])

    organization_api_key =
      insert(:key, organization: owned_org, permissions: [build(:key_permission, domain: "api")])

    user_repo_key =
      insert(
        :key,
        user: user,
        permissions: [build(:key_permission, domain: "repository", resource: owned_org.name)]
      )

    organization_repo_key =
      insert(
        :key,
        organization: owned_org,
        permissions: [build(:key_permission, domain: "repository", resource: owned_org.name)]
      )

    user_all_repos_key =
      insert(:key, user: user, permissions: [build(:key_permission, domain: "repositories")])

    unowned_user_repo_key =
      insert(
        :key,
        user: user,
        permissions: [build(:key_permission, domain: "repository", resource: unowned_org.name)]
      )

    {:ok,
     [
       owned_org: owned_org,
       unowned_org: unowned_org,
       user: user,
       user_full_key: user_full_key,
       user_api_key: user_api_key,
       user_repo_key: user_repo_key,
       user_all_repos_key: user_all_repos_key,
       unowned_user_repo_key: unowned_user_repo_key,
       organization_full_key: organization_full_key,
       organization_api_key: organization_api_key,
       organization_repo_key: organization_repo_key
     ]}
  end

  describe "GET /api/auth" do
    test "without key" do
      build_conn()
      |> get("api/auth", domain: "api")
      |> response(401)
    end

    test "with invalid key" do
      build_conn()
      |> put_req_header("authorization", "ABC")
      |> get("api/auth", domain: "api")
      |> response(401)
    end

    test "without domain returns 400", %{user_full_key: key} do
      build_conn()
      |> put_req_header("authorization", key.user_secret)
      |> get("api/auth")
      |> response(400)
    end

    test "with revoked key", %{user: user} do
      key =
        insert(
          :key,
          user: user,
          permissions: [build(:key_permission, domain: "api")],
          revoked_at: ~N[2018-01-01 00:00:00]
        )

      build_conn()
      |> put_req_header("authorization", key.user_secret)
      |> get("api/auth", domain: "api")
      |> response(401)

      key =
        insert(
          :key,
          user: user,
          permissions: [build(:key_permission, domain: "api")],
          revoke_at: ~N[2018-01-01 00:00:00]
        )

      build_conn()
      |> put_req_header("authorization", key.user_secret)
      |> get("api/auth", domain: "api")
      |> response(401)

      key =
        insert(
          :key,
          user: user,
          permissions: [build(:key_permission, domain: "api")],
          revoke_at: ~N[2030-01-01 00:00:00]
        )

      build_conn()
      |> put_req_header("authorization", key.user_secret)
      |> get("api/auth", domain: "api")
      |> response(204)
    end

    test "authenticate full user key", %{
      user_full_key: key,
      owned_org: owned_org,
      unowned_org: unowned_org
    } do
      build_conn()
      |> put_req_header("authorization", key.user_secret)
      |> get("api/auth", domain: "api")
      |> response(204)

      build_conn()
      |> put_req_header("authorization", key.user_secret)
      |> get("api/auth", domain: "repository", resource: owned_org.name)
      |> response(204)

      build_conn()
      |> put_req_header("authorization", key.user_secret)
      |> get("api/auth", domain: "repository", resource: unowned_org.name)
      |> response(401)

      build_conn()
      |> put_req_header("authorization", key.user_secret)
      |> get("api/auth", domain: "repository", resource: "BADREPO")
      |> response(401)

      build_conn()
      |> put_req_header("authorization", key.user_secret)
      |> get("api/auth", domain: "repository")
      |> response(401)
    end

    test "authenticate full organization key", %{
      organization_full_key: key,
      owned_org: owned_org,
      unowned_org: unowned_org
    } do
      build_conn()
      |> put_req_header("authorization", key.user_secret)
      |> get("api/auth", domain: "api")
      |> response(204)

      build_conn()
      |> put_req_header("authorization", key.user_secret)
      |> get("api/auth", domain: "repository", resource: owned_org.name)
      |> response(204)

      build_conn()
      |> put_req_header("authorization", key.user_secret)
      |> get("api/auth", domain: "repository", resource: unowned_org.name)
      |> response(401)

      build_conn()
      |> put_req_header("authorization", key.user_secret)
      |> get("api/auth", domain: "repository", resource: "BADREPO")
      |> response(401)

      build_conn()
      |> put_req_header("authorization", key.user_secret)
      |> get("api/auth", domain: "repository")
      |> response(401)
    end

    test "authenticate user api key", %{user_api_key: key} do
      build_conn()
      |> put_req_header("authorization", key.user_secret)
      |> get("api/auth", domain: "api")
      |> response(204)

      build_conn()
      |> put_req_header("authorization", key.user_secret)
      |> get("api/auth", domain: "api", resource: "read")
      |> response(204)

      build_conn()
      |> put_req_header("authorization", key.user_secret)
      |> get("api/auth", domain: "api", resource: "write")
      |> response(204)

      build_conn()
      |> put_req_header("authorization", key.user_secret)
      |> get("api/auth", domain: "repository", resource: "myrepo")
      |> response(401)
    end

    test "authenticate organization api key", %{organization_api_key: key} do
      build_conn()
      |> put_req_header("authorization", key.user_secret)
      |> get("api/auth", domain: "api")
      |> response(204)

      build_conn()
      |> put_req_header("authorization", key.user_secret)
      |> get("api/auth", domain: "api", resource: "read")
      |> response(204)

      build_conn()
      |> put_req_header("authorization", key.user_secret)
      |> get("api/auth", domain: "api", resource: "write")
      |> response(204)

      build_conn()
      |> put_req_header("authorization", key.user_secret)
      |> get("api/auth", domain: "repository", resource: "myrepo")
      |> response(401)
    end

    test "authenticate user read api key", %{user: user} do
      permission = build(:key_permission, domain: "api", resource: "read")
      key = insert(:key, user: user, permissions: [permission])

      build_conn()
      |> put_req_header("authorization", key.user_secret)
      |> get("api/auth", domain: "api", resource: "read")
      |> response(204)

      build_conn()
      |> put_req_header("authorization", key.user_secret)
      |> get("api/auth", domain: "api", resource: "write")
      |> response(401)
    end

    test "authenticate user write api key", %{user: user} do
      permission = build(:key_permission, domain: "api", resource: "write")
      key = insert(:key, user: user, permissions: [permission])

      build_conn()
      |> put_req_header("authorization", key.user_secret)
      |> get("api/auth", domain: "api", resource: "write")
      |> response(204)

      build_conn()
      |> put_req_header("authorization", key.user_secret)
      |> get("api/auth", domain: "repository", resource: "foo")
      |> response(401)
    end

    test "authenticate organization read api key", %{owned_org: owned_org} do
      permission = build(:key_permission, domain: "api", resource: "read")
      key = insert(:key, organization: owned_org, permissions: [permission])

      build_conn()
      |> put_req_header("authorization", key.user_secret)
      |> get("api/auth", domain: "api", resource: "read")
      |> response(204)

      build_conn()
      |> put_req_header("authorization", key.user_secret)
      |> get("api/auth", domain: "api", resource: "write")
      |> response(401)
    end

    test "authenticate organization write api key", %{owned_org: owned_org} do
      permission = build(:key_permission, domain: "api", resource: "write")
      key = insert(:key, organization: owned_org, permissions: [permission])

      build_conn()
      |> put_req_header("authorization", key.user_secret)
      |> get("api/auth", domain: "api", resource: "write")
      |> response(204)

      build_conn()
      |> put_req_header("authorization", key.user_secret)
      |> get("api/auth", domain: "repository", resource: owned_org.name)
      |> response(401)
    end

    test "authenticate user repo key with all repositories", %{
      user_all_repos_key: key,
      owned_org: owned_org,
      unowned_org: unowned_org
    } do
      build_conn()
      |> put_req_header("authorization", key.user_secret)
      |> get("api/auth", domain: "api")
      |> response(401)

      build_conn()
      |> put_req_header("authorization", key.user_secret)
      |> get("api/auth", domain: "repositories")
      |> response(204)

      build_conn()
      |> put_req_header("authorization", key.user_secret)
      |> get("api/auth", domain: "repository", resource: owned_org.name)
      |> response(204)

      build_conn()
      |> put_req_header("authorization", key.user_secret)
      |> get("api/auth", domain: "repository", resource: unowned_org.name)
      |> response(403)

      build_conn()
      |> put_req_header("authorization", key.user_secret)
      |> get("api/auth", domain: "repository", resource: "BADREPO")
      |> response(403)
    end

    test "authenticate docs key", %{user: user, owned_org: owned_org} do
      permission = build(:key_permission, domain: "docs", resource: owned_org.name)
      key = insert(:key, user: user, permissions: [permission])

      build_conn()
      |> put_req_header("authorization", key.user_secret)
      |> get("api/auth", domain: "docs", resource: owned_org.name)
      |> response(204)

      build_conn()
      |> put_req_header("authorization", key.user_secret)
      |> get("api/auth", domain: "docs", resource: "not_my_org")
      |> response(401)
    end

    test "authenticate repository key against repository without access permissions", %{
      unowned_user_repo_key: key,
      unowned_org: unowned_org
    } do
      build_conn()
      |> put_req_header("authorization", key.user_secret)
      |> get("api/auth", domain: "repository", resource: unowned_org.name)
      |> response(403)
    end

    test "authenticate user repository key without active billing", %{user: user} do
      organization = insert(:organization, billing_active: false)
      insert(:organization_user, organization: organization, user: user)

      key =
        insert(
          :key,
          user: user,
          permissions: [build(:key_permission, domain: "repository", resource: organization.name)]
        )

      build_conn()
      |> put_req_header("authorization", key.user_secret)
      |> get("api/auth", domain: "repository", resource: organization.name)
      |> response(403)
    end

    test "authenticate organization repository key without active billing" do
      organization = insert(:organization, billing_active: false)

      key =
        insert(
          :key,
          organization: organization,
          permissions: [build(:key_permission, domain: "repository", resource: organization.name)]
        )

      build_conn()
      |> put_req_header("authorization", key.user_secret)
      |> get("api/auth", domain: "repository", resource: organization.name)
      |> response(403)
    end
  end
end
