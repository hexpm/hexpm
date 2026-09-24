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
      |> get("/api/auth", domain: "api")
      |> response(401)
    end

    test "with invalid key" do
      build_conn()
      |> put_req_header("authorization", "ABC")
      |> get("/api/auth", domain: "api")
      |> response(401)

      assert_received {Hexpm.LogLines, :warning,
                       %{method: "api_key", reason: "invalid", path: "/api/auth"} = event}

      refute Map.has_key?(event, :key_id)
    end

    test "without domain returns 400", %{user_full_key: key} do
      build_conn()
      |> put_req_header("authorization", key.user_secret)
      |> get("/api/auth")
      |> response(400)
    end

    test "with revoked key", %{user: user} do
      key =
        insert(
          :key,
          user: user,
          permissions: [build(:key_permission, domain: "api")],
          revoke_at: ~N[2018-01-01 00:00:00]
        )

      build_conn()
      |> put_req_header("authorization", key.user_secret)
      |> get("/api/auth", domain: "api")
      |> response(401)

      key_id = key.id
      user_id = user.id

      assert_received {Hexpm.LogLines, :warning,
                       %{method: "api_key", reason: "revoked", key_id: ^key_id, user_id: ^user_id}}

      key =
        insert(
          :key,
          user: user,
          permissions: [build(:key_permission, domain: "api")],
          revoke_at: ~N[2018-01-01 00:00:00]
        )

      build_conn()
      |> put_req_header("authorization", key.user_secret)
      |> get("/api/auth", domain: "api")
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
      |> get("/api/auth", domain: "api")
      |> response(200)
    end

    test "authenticate full user key", %{
      user_full_key: key,
      owned_org: owned_org,
      unowned_org: unowned_org
    } do
      build_conn()
      |> put_req_header("authorization", key.user_secret)
      |> get("/api/auth", domain: "api")
      |> response(200)

      build_conn()
      |> put_req_header("authorization", key.user_secret)
      |> get("/api/auth", domain: "repository", resource: owned_org.name)
      |> response(200)

      build_conn()
      |> put_req_header("authorization", key.user_secret)
      |> get("/api/auth", domain: "repository", resource: unowned_org.name)
      |> response(401)

      build_conn()
      |> put_req_header("authorization", key.user_secret)
      |> get("/api/auth", domain: "repository", resource: "BADREPO")
      |> response(401)

      build_conn()
      |> put_req_header("authorization", key.user_secret)
      |> get("/api/auth", domain: "repository")
      |> response(401)
    end

    test "authenticate full organization key", %{
      organization_full_key: key,
      owned_org: owned_org,
      unowned_org: unowned_org
    } do
      build_conn()
      |> put_req_header("authorization", key.user_secret)
      |> get("/api/auth", domain: "api")
      |> response(200)

      build_conn()
      |> put_req_header("authorization", key.user_secret)
      |> get("/api/auth", domain: "repository", resource: owned_org.name)
      |> response(200)

      build_conn()
      |> put_req_header("authorization", key.user_secret)
      |> get("/api/auth", domain: "repository", resource: unowned_org.name)
      |> response(401)

      build_conn()
      |> put_req_header("authorization", key.user_secret)
      |> get("/api/auth", domain: "repository", resource: "BADREPO")
      |> response(401)

      build_conn()
      |> put_req_header("authorization", key.user_secret)
      |> get("/api/auth", domain: "repository")
      |> response(401)
    end

    test "refuses an organization key asking about another organization", %{
      owned_org: owned_org,
      unowned_org: unowned_org
    } do
      key =
        insert(:key,
          organization: owned_org,
          permissions: [build(:key_permission, domain: "repositories")]
        )

      build_conn()
      |> put_req_header("authorization", key.user_secret)
      |> get("/api/auth", domain: "repository", resource: unowned_org.name)
      |> response(403)
    end

    test "authenticate user api key", %{user_api_key: key} do
      conn =
        build_conn()
        |> put_req_header("authorization", key.user_secret)
        |> get("/api/auth", domain: "api")

      assert response(conn, 200)
      assert get_resp_header(conn, "x-hex-key-id") == [Integer.to_string(key.id)]

      build_conn()
      |> put_req_header("authorization", key.user_secret)
      |> get("/api/auth", domain: "api", resource: "read")
      |> response(200)

      build_conn()
      |> put_req_header("authorization", key.user_secret)
      |> get("/api/auth", domain: "api", resource: "write")
      |> response(200)

      build_conn()
      |> put_req_header("authorization", key.user_secret)
      |> get("/api/auth", domain: "repository", resource: "myrepo")
      |> response(401)
    end

    test "authenticate organization api key", %{organization_api_key: key} do
      build_conn()
      |> put_req_header("authorization", key.user_secret)
      |> get("/api/auth", domain: "api")
      |> response(200)

      build_conn()
      |> put_req_header("authorization", key.user_secret)
      |> get("/api/auth", domain: "api", resource: "read")
      |> response(200)

      build_conn()
      |> put_req_header("authorization", key.user_secret)
      |> get("/api/auth", domain: "api", resource: "write")
      |> response(200)

      build_conn()
      |> put_req_header("authorization", key.user_secret)
      |> get("/api/auth", domain: "repository", resource: "myrepo")
      |> response(401)
    end

    test "authenticate user key returns key owner", %{user_api_key: key, user: user} do
      body =
        build_conn()
        |> put_req_header("authorization", key.user_secret)
        |> get("/api/auth", domain: "api")
        |> json_response(200)

      assert body == %{
               "key" => %{
                 "name" => key.name,
                 "owner" => %{"type" => "user", "name" => user.username}
               }
             }
    end

    test "authenticate organization key returns key owner", %{
      organization_api_key: key,
      owned_org: owned_org
    } do
      body =
        build_conn()
        |> put_req_header("authorization", key.user_secret)
        |> get("/api/auth", domain: "api")
        |> json_response(200)

      assert body == %{
               "key" => %{
                 "name" => key.name,
                 "owner" => %{"type" => "organization", "name" => owned_org.name}
               }
             }
    end

    test "authenticate oauth token returns no content", %{user: user} do
      client = insert(:oauth_client)
      oauth_session = insert(:oauth_session, user: user, client_id: client.client_id)

      {:ok, oauth_token} =
        Hexpm.OAuth.Tokens.create_and_insert_for_user(
          user,
          client.client_id,
          ["api:read"],
          "authorization_code",
          "test_grant_ref",
          user_session_id: oauth_session.id
        )

      build_conn()
      |> put_req_header("authorization", "Bearer #{oauth_token.access_token}")
      |> get("/api/auth", domain: "api")
      |> response(204)
    end

    test "authenticate user read api key", %{user: user} do
      permission = build(:key_permission, domain: "api", resource: "read")
      key = insert(:key, user: user, permissions: [permission])

      build_conn()
      |> put_req_header("authorization", key.user_secret)
      |> get("/api/auth", domain: "api", resource: "read")
      |> response(200)

      build_conn()
      |> put_req_header("authorization", key.user_secret)
      |> get("/api/auth", domain: "api", resource: "write")
      |> response(401)
    end

    test "authenticate user write api key", %{user: user} do
      permission = build(:key_permission, domain: "api", resource: "write")
      key = insert(:key, user: user, permissions: [permission])

      build_conn()
      |> put_req_header("authorization", key.user_secret)
      |> get("/api/auth", domain: "api", resource: "write")
      |> response(200)

      build_conn()
      |> put_req_header("authorization", key.user_secret)
      |> get("/api/auth", domain: "repository", resource: "foo")
      |> response(401)
    end

    test "authenticate organization read api key", %{owned_org: owned_org} do
      permission = build(:key_permission, domain: "api", resource: "read")
      key = insert(:key, organization: owned_org, permissions: [permission])

      build_conn()
      |> put_req_header("authorization", key.user_secret)
      |> get("/api/auth", domain: "api", resource: "read")
      |> response(200)

      build_conn()
      |> put_req_header("authorization", key.user_secret)
      |> get("/api/auth", domain: "api", resource: "write")
      |> response(401)
    end

    test "authenticate organization write api key", %{owned_org: owned_org} do
      permission = build(:key_permission, domain: "api", resource: "write")
      key = insert(:key, organization: owned_org, permissions: [permission])

      build_conn()
      |> put_req_header("authorization", key.user_secret)
      |> get("/api/auth", domain: "api", resource: "write")
      |> response(200)

      build_conn()
      |> put_req_header("authorization", key.user_secret)
      |> get("/api/auth", domain: "repository", resource: owned_org.name)
      |> response(401)
    end

    test "authenticate user repo key with all repositories", %{
      user_all_repos_key: key,
      owned_org: owned_org,
      unowned_org: unowned_org
    } do
      build_conn()
      |> put_req_header("authorization", key.user_secret)
      |> get("/api/auth", domain: "api")
      |> response(401)

      build_conn()
      |> put_req_header("authorization", key.user_secret)
      |> get("/api/auth", domain: "repositories")
      |> response(200)

      build_conn()
      |> put_req_header("authorization", key.user_secret)
      |> get("/api/auth", domain: "repository", resource: owned_org.name)
      |> response(200)

      build_conn()
      |> put_req_header("authorization", key.user_secret)
      |> get("/api/auth", domain: "repository", resource: unowned_org.name)
      |> response(403)

      build_conn()
      |> put_req_header("authorization", key.user_secret)
      |> get("/api/auth", domain: "repository", resource: "BADREPO")
      |> response(403)
    end

    test "authenticate docs key", %{user: user, owned_org: owned_org} do
      permission = build(:key_permission, domain: "docs", resource: owned_org.name)
      key = insert(:key, user: user, permissions: [permission])

      build_conn()
      |> put_req_header("authorization", key.user_secret)
      |> get("/api/auth", domain: "docs", resource: owned_org.name)
      |> response(200)

      build_conn()
      |> put_req_header("authorization", key.user_secret)
      |> get("/api/auth", domain: "docs", resource: "not_my_org")
      |> response(401)
    end

    test "authenticate oauth token against a package", %{user: user, owned_org: owned_org} do
      repository = insert(:repository, organization: owned_org, name: owned_org.name)
      package = insert(:package, repository_id: repository.id)
      insert(:package_owner, package: package, user: user)
      token = oauth_token(user, ["api"])

      build_conn()
      |> put_req_header("authorization", "Bearer #{token.access_token}")
      |> get("/api/auth", domain: "package", resource: "#{owned_org.name}/#{package.name}")
      |> response(204)

      build_conn()
      |> put_req_header("authorization", "Bearer #{token.access_token}")
      |> get("/api/auth", domain: "package", resource: "#{owned_org.name}/nonexistent")
      |> response(403)
    end

    # A resource-only domain with no resource used to reach String.split/2 with
    # nil and answer 500.
    test "refuses a resource-less request rather than falling over", %{user: user} do
      token = oauth_token(user, ["api"])

      for {domain, status} <- [{"package", 403}, {"repository", 401}, {"docs", 401}] do
        build_conn()
        |> put_req_header("authorization", "Bearer #{token.access_token}")
        |> get("/api/auth", domain: domain)
        |> response(status)
      end
    end

    test "authenticate oauth token against a package without active billing", %{user: user} do
      organization = insert(:organization, billing_active: false)
      insert(:organization_user, organization: organization, user: user)
      repository = insert(:repository, organization: organization, name: organization.name)
      package = insert(:package, repository_id: repository.id)
      insert(:package_owner, package: package, user: user)
      token = oauth_token(user, ["api"])

      build_conn()
      |> put_req_header("authorization", "Bearer #{token.access_token}")
      |> get("/api/auth", domain: "package", resource: "#{organization.name}/#{package.name}")
      |> response(403)
    end

    test "authenticate repository key against repository without access permissions", %{
      unowned_user_repo_key: key,
      unowned_org: unowned_org
    } do
      build_conn()
      |> put_req_header("authorization", key.user_secret)
      |> get("/api/auth", domain: "repository", resource: unowned_org.name)
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
      |> get("/api/auth", domain: "repository", resource: organization.name)
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
      |> get("/api/auth", domain: "repository", resource: organization.name)
      |> response(403)
    end
  end

  defp oauth_token(user, scopes) do
    client = insert(:oauth_client)
    session = insert(:oauth_session, user: user, client_id: client.client_id)

    {:ok, token} =
      Hexpm.OAuth.Tokens.create_and_insert_for_user(
        user,
        client.client_id,
        scopes,
        "authorization_code",
        "test_grant_ref-#{System.unique_integer([:positive])}",
        user_session_id: session.id
      )

    token
  end
end
