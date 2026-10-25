defmodule HexpmWeb.KeyCapabilitiesTest do
  use HexpmWeb.ConnCase, async: true

  import Mox

  setup :verify_on_exit!

  defp mock_customer(_organization) do
    stub(Hexpm.Billing.Mock, :get, fn _token, _opts ->
      %{"checkout_html" => "", "invoices" => []}
    end)
  end

  setup do
    repository = insert(:repository)
    organization = repository.organization
    package = insert(:package, repository_id: repository.id)
    other_package = insert(:package, repository_id: repository.id)
    insert(:release, package: package, version: "1.0.0")
    insert(:release, package: other_package, version: "1.0.0")

    admin = insert(:user_with_tfa)
    writer = insert(:user_with_tfa)
    reader = insert(:user_with_tfa)
    insert(:organization_user, organization: organization, user: admin, role: "admin")
    insert(:organization_user, organization: organization, user: writer, role: "write")
    insert(:organization_user, organization: organization, user: reader, role: "read")

    %{
      organization: organization,
      package: package,
      other_package: other_package,
      admin: admin,
      writer: writer,
      reader: reader
    }
  end

  defp signed_in(user, scopes \\ ["api"]), do: test_oauth_login(build_conn(), user, scopes)

  defp with_key(secret), do: put_req_header(build_conn(), "authorization", secret)

  defp create_key(conn, organization, permissions) do
    params =
      if permissions == :omitted,
        do: %{name: "ci"},
        else: %{name: "ci", permissions: permissions}

    post(conn, "/api/orgs/#{organization.name}/keys", params)
  end

  defp created_secret(conn), do: json_response(conn, 201)["secret"]

  defp permissions(conn) do
    conn
    |> json_response(201)
    |> Map.fetch!("permissions")
    |> Enum.map(
      &Hexpm.Permissions.permission_to_scope(%{domain: &1["domain"], resource: &1["resource"]})
    )
    |> Enum.sort()
  end

  defp errors(conn), do: inspect(json_response(conn, 422)["errors"])

  defp org_key(organization, permissions) do
    {:ok, %{key: key}} =
      Hexpm.Accounts.Keys.create(
        organization,
        %{
          name: "org",
          permissions: Enum.map(permissions, &Hexpm.Permissions.scope_to_permission/1)
        },
        audit: audit_data(organization.user)
      )

    key.user_secret
  end

  defp retire(secret, organization, package) do
    build_conn()
    |> put_req_header("authorization", secret)
    |> post("/api/repos/#{organization.name}/packages/#{package.name}/releases/1.0.0/retire", %{
      "reason" => "security"
    })
  end

  defp add_owner(secret, organization, package, user) do
    build_conn()
    |> put_req_header("authorization", secret)
    |> put("/api/repos/#{organization.name}/packages/#{package.name}/owners/#{user.username}")
  end

  defp add_member(secret, organization) do
    build_conn()
    |> put_req_header("authorization", secret)
    |> post("/api/orgs/#{organization.name}/members", %{
      "name" => insert(:user).username,
      "role" => "admin"
    })
  end

  describe "write member" do
    test "asking for api:write gets api:read, publish and keys", c do
      conn =
        create_key(signed_in(c.writer), c.organization, [%{domain: "api", resource: "write"}])

      assert permissions(conn) == ["api:read", "keys", "publish"]

      conn = create_key(signed_in(c.writer), c.organization, :omitted)
      assert permissions(conn) == ["api:read", "keys", "publish"]
    end

    test "grants only the permissions of the write role", c do
      for scope <- [
            "members",
            "owners",
            "administration",
            "package:#{c.organization.name}/#{c.package.name}",
            "owners:#{c.organization.name}/#{c.package.name}"
          ] do
        conn =
          create_key(signed_in(c.writer), c.organization, [
            Hexpm.Permissions.scope_to_permission(scope)
          ])

        assert errors(conn) =~ "requires the admin role in #{c.organization.name}", scope
      end
    end

    test "the key it gets publishes, doesn't manage owners or members and can't create keys", c do
      conn =
        create_key(signed_in(c.writer), c.organization, [%{domain: "api", resource: "write"}])

      secret = created_secret(conn)

      assert retire(secret, c.organization, c.package).status == 204
      assert add_owner(secret, c.organization, c.package, c.reader).status == 401
      assert add_member(secret, c.organization).status == 401

      assert create_key(with_key(secret), c.organization, [%{domain: "publish"}]).status == 403
    end

    test "can't create keys for an organization it isn't in", c do
      other = insert(:repository).organization
      assert create_key(signed_in(c.writer), other, :omitted).status == 404
    end

    test "a single package publish key only reaches that package", c do
      resource = "#{c.organization.name}/#{c.package.name}"

      conn =
        create_key(signed_in(c.writer), c.organization, [%{domain: "publish", resource: resource}])

      assert permissions(conn) == ["publish:#{resource}"]
      secret = created_secret(conn)

      assert retire(secret, c.organization, c.package).status == 204
      assert retire(secret, c.organization, c.other_package).status == 401
      assert add_owner(secret, c.organization, c.package, c.reader).status == 401
    end
  end

  describe "read member" do
    test "creates read keys and nothing more", c do
      conn =
        create_key(signed_in(c.reader), c.organization, [
          %{domain: "repository", resource: c.organization.name},
          %{domain: "api", resource: "read"}
        ])

      assert permissions(conn) == ["api:read", "repository:#{c.organization.name}"]

      conn = create_key(signed_in(c.reader), c.organization, :omitted)
      assert permissions(conn) == ["api:read"]

      conn = create_key(signed_in(c.reader), c.organization, [%{domain: "publish"}])
      assert errors(conn) =~ "publish requires the write role"
    end

    test "can't revoke keys", c do
      org_key(c.organization, ["api:read"])

      build_conn()
      |> put_req_header("authorization", key_for(c.reader))
      |> delete("/api/orgs/#{c.organization.name}/keys/org")
      |> response(404)

      assert Hexpm.Accounts.Keys.get(c.organization, "org")
    end
  end

  describe "an empty permission list" do
    test "is read as the default request", c do
      for permissions <- [[], %{}] do
        conn = create_key(signed_in(c.reader), c.organization, permissions)
        assert permissions(conn) == ["api:read"]

        conn = create_key(signed_in(c.writer), c.organization, permissions)
        assert permissions(conn) == ["api:read", "keys", "publish"]
      end
    end
  end

  describe "admin" do
    test "gets api:write as asked", c do
      conn = create_key(signed_in(c.admin), c.organization, [%{domain: "api", resource: "write"}])
      assert permissions(conn) == ["api:write"]
      secret = created_secret(conn)

      assert add_owner(secret, c.organization, c.package, c.reader).status == 204
    end

    test "can grant every permission", c do
      resource = "#{c.organization.name}/#{c.package.name}"

      conn =
        create_key(signed_in(c.admin), c.organization, [
          %{domain: "members"},
          %{domain: "administration"},
          %{domain: "owners", resource: resource},
          %{domain: "package", resource: resource}
        ])

      assert permissions(conn) ==
               ["administration", "members", "owners:#{resource}", "package:#{resource}"]
    end

    test "is limited by the scopes it signs in with", c do
      conn = create_key(signed_in(c.admin, ["keys"]), c.organization, [%{domain: "members"}])
      assert errors(conn) =~ "members is not held by the authenticating key"
    end
  end

  describe "organization key" do
    test "can't create keys, whatever it holds", c do
      secret = org_key(c.organization, ["keys", "publish"])

      conn = create_key(with_key(secret), c.organization, [%{domain: "publish"}])
      assert json_response(conn, 403)["message"] =~ "API keys cannot create API keys"
    end

    test "gets the same answer for an organization that exists and one that doesn't", c do
      secret = org_key(c.organization, ["api:write"])

      existing = create_key(with_key(secret), insert(:repository).organization, :omitted)
      missing = create_key(with_key(secret), %{name: "nosuchorganization"}, :omitted)

      assert existing.status == 403
      assert missing.status == 403
    end
  end

  describe "personal keys" do
    test "a sign-in holding only keys can't create a full API key", c do
      for params <- [
            %{name: "laptop", permissions: [%{domain: "api", resource: "write"}]},
            %{name: "laptop"}
          ] do
        conn = c.writer |> signed_in(["keys"]) |> post("/api/keys", params)
        assert permissions(conn) == ["keys"]
      end

      conn =
        c.writer
        |> signed_in(["keys"])
        |> post("/api/keys", %{name: "laptop", permissions: [%{domain: "publish"}]})

      assert errors(conn) =~ "publish is not held by the authenticating key"
    end

    test "a full sign-in creates capability keys", c do
      conn =
        c.writer
        |> signed_in()
        |> post("/api/keys", %{
          name: "laptop",
          permissions: [
            %{domain: "publish", resource: "#{c.organization.name}/#{c.package.name}"},
            %{domain: "api", resource: "read"}
          ]
        })

      assert permissions(conn) == ["api:read", "publish:#{c.organization.name}/#{c.package.name}"]
      secret = created_secret(conn)

      assert retire(secret, c.organization, c.package).status == 204
      assert retire(secret, c.organization, c.other_package).status == 401
    end

    test "a token passes a package permission on only with API reads" do
      user =
        insert(:user,
          tfa: %Hexpm.Accounts.TFA{secret: Hexpm.Accounts.TFA.generate_secret()}
        )

      package = insert(:package, package_owners: [build(:package_owner, user: user)])
      client = insert(:oauth_client)
      session = insert(:oauth_session, user: user, client_id: client.client_id)
      permissions = [%{domain: "package", resource: "hexpm/#{package.name}"}]

      create = fn scopes ->
        {:ok, token} =
          Hexpm.OAuth.Tokens.create_and_insert_for_user(
            user,
            client.client_id,
            scopes,
            "authorization_code",
            "test_grant_ref",
            user_session_id: session.id
          )

        build_conn()
        |> put_req_header("authorization", "Bearer #{token.access_token}")
        |> put_req_header("x-hex-otp", Hexpm.Accounts.TFA.time_based_token(user.tfa.secret))
        |> post("/api/keys", %{name: "laptop", permissions: permissions})
      end

      assert errors(create.(["keys", "package:hexpm/#{package.name}"])) =~
               "package:hexpm/#{package.name} is not held by the authenticating key"

      assert permissions(create.(["keys", "api:read", "package:hexpm/#{package.name}"])) ==
               ["package:hexpm/#{package.name}"]
    end

    test "owners on one package needs full ownership", c do
      conn =
        c.writer
        |> signed_in()
        |> post("/api/keys", %{
          name: "laptop",
          permissions: [%{domain: "owners", resource: "#{c.organization.name}/#{c.package.name}"}]
        })

      assert errors(conn) =~ "you do not have access to this package"
    end
  end

  test "a user token with a capability needs a TOTP code to write", c do
    writer = insert(:user)
    insert(:organization_user, organization: c.organization, user: writer, role: "write")
    client = insert(:oauth_client)
    session = insert(:oauth_session, user: writer, client_id: client.client_id)

    {:ok, token} =
      Hexpm.OAuth.Tokens.create_and_insert_for_user(
        writer,
        client.client_id,
        ["publish"],
        "authorization_code",
        "test_grant_ref",
        user_session_id: session.id
      )

    conn = retire("Bearer #{token.access_token}", c.organization, c.package)

    assert conn.status == 403
    assert json_response(conn, 403)["message"] =~ "Two-factor authentication must be enabled"
  end

  describe "dashboard" do
    test "a write member's form is limited to their role", c do
      mock_customer(c.organization)

      conn =
        build_conn()
        |> test_login(c.writer)
        |> post("/dashboard/orgs/#{c.organization.name}/keys", %{
          key: %{name: "ci", permissions: %{capabilities: %{members: "on"}}}
        })

      assert response(conn, 400) =~ "members requires the admin role"

      conn =
        build_conn()
        |> test_login(c.writer)
        |> post("/dashboard/orgs/#{c.organization.name}/keys", %{
          key: %{
            name: "ci",
            permissions: %{
              capabilities: %{publish: "on"},
              publish: %{"#{c.organization.name}/#{c.package.name}" => "on"}
            }
          }
        })

      assert redirected_to(conn) == "/dashboard/orgs/#{c.organization.name}/keys"

      assert [key] = Hexpm.Accounts.Keys.all(c.organization)

      assert Enum.map(key.permissions, &{&1.domain, &1.resource}) == [
               {"publish", nil},
               {"publish", "#{c.organization.name}/#{c.package.name}"}
             ]
    end

    test "the modal shows which permissions need a higher role", c do
      mock_customer(c.organization)

      body =
        build_conn()
        |> test_login(c.writer)
        |> get("/dashboard/orgs/#{c.organization.name}/keys")
        |> html_response(200)

      assert body =~ "Write permissions"
      assert body =~ "Requires admin"
      assert body =~ ~s(name="key[permissions][capabilities][publish]")
    end
  end

  test "nobody creates keys for the public organization", c do
    conn =
      c.reader
      |> signed_in()
      |> post("/api/orgs/hexpm/keys", %{
        name: "ci",
        permissions: [%{domain: "api", resource: "read"}]
      })

    assert conn.status == 403
  end

  describe "GET /api/auth" do
    test "a capability answers the api write probe", c do
      secret = org_key(c.organization, ["publish"])

      build_conn()
      |> put_req_header("authorization", secret)
      |> get("/api/auth", domain: "api", resource: "write")
      |> response(200)

      build_conn()
      |> put_req_header("authorization", secret)
      |> get("/api/auth", domain: "members")
      |> response(401)
    end

    test "api:write answers new domains and keeps its package answer", c do
      secret = org_key(c.organization, ["api:write"])

      build_conn()
      |> put_req_header("authorization", secret)
      |> get("/api/auth", domain: "members")
      |> response(200)

      build_conn()
      |> put_req_header("authorization", secret)
      |> get("/api/auth", domain: "package", resource: "#{c.organization.name}/#{c.package.name}")
      |> response(401)
    end
  end

  describe "client_credentials" do
    setup do
      %{client: insert(:oauth_client)}
    end

    test "a capability key asking for api:write gets its capabilities", c do
      secret = org_key(c.organization, ["publish", "keys", "api:read"])

      response =
        build_conn()
        |> post(~p"/api/oauth/token", %{
          "grant_type" => "client_credentials",
          "client_id" => c.client.client_id,
          "client_secret" => secret,
          "scope" => "api:write"
        })
        |> json_response(200)

      assert response["scope"] |> String.split() |> Enum.sort() == ["api:read", "keys", "publish"]

      token = response["access_token"]

      assert build_conn()
             |> put_req_header("authorization", "Bearer #{token}")
             |> then(&retire_with(&1, c.organization, c.package))
             |> Map.fetch!(:status) == 204

      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token}")
        |> add_member_with(c.organization)

      assert conn.status == 403
      assert get_resp_header(conn, "www-authenticate") |> hd() =~ "insufficient_scope"
    end

    test "a full key exchanges for a capability scope", c do
      secret = org_key(c.organization, ["api:write"])

      response =
        build_conn()
        |> post(~p"/api/oauth/token", %{
          "grant_type" => "client_credentials",
          "client_id" => c.client.client_id,
          "client_secret" => secret,
          "scope" => "publish"
        })
        |> json_response(200)

      assert response["scope"] == "publish"
      token = response["access_token"]

      assert build_conn()
             |> put_req_header("authorization", "Bearer #{token}")
             |> then(&retire_with(&1, c.organization, c.package))
             |> Map.fetch!(:status) == 204

      assert build_conn()
             |> put_req_header("authorization", "Bearer #{token}")
             |> add_member_with(c.organization)
             |> Map.fetch!(:status) == 403
    end

    test "a key holding no capability is refused api:write", c do
      secret = org_key(c.organization, ["api:read"])

      build_conn()
      |> post(~p"/api/oauth/token", %{
        "grant_type" => "client_credentials",
        "client_id" => c.client.client_id,
        "client_secret" => secret,
        "scope" => "api:write"
      })
      |> json_response(400)
    end
  end

  defp retire_with(conn, organization, package) do
    post(
      conn,
      "/api/repos/#{organization.name}/packages/#{package.name}/releases/1.0.0/retire",
      %{
        "reason" => "security"
      }
    )
  end

  defp add_member_with(conn, organization) do
    post(conn, "/api/orgs/#{organization.name}/members", %{
      "name" => insert(:user).username,
      "role" => "admin"
    })
  end
end
