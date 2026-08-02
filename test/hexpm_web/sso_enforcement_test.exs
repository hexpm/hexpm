defmodule HexpmWeb.SSOEnforcementTest do
  use HexpmWeb.ConnCase, async: false

  alias Hexpm.Accounts.SSO
  alias Hexpm.Emails.OutboxEntry

  setup do
    organization = insert(:organization)
    repository = insert(:repository, organization: organization, name: organization.name)
    package = insert(:package, repository_id: repository.id)
    insert(:release, package: package, version: "1.0.0")

    admin = insert(:user, emails: [build(:email, verified: true, primary: true)])
    member = insert(:user, emails: [build(:email, verified: true, primary: true)])
    insert(:organization_user, organization: organization, user: admin, role: "admin")
    insert(:organization_user, organization: organization, user: member, role: "write")

    config = Application.fetch_env!(:hexpm, :organization_sso)

    Application.put_env(
      :hexpm,
      :organization_sso,
      Keyword.merge(config, mode: :beta, beta_organizations: [organization.name])
    )

    on_exit(fn -> Application.put_env(:hexpm, :organization_sso, config) end)

    connection =
      insert(:organization_sso_connection,
        organization: organization,
        tested_at: DateTime.utc_now(),
        enabled_at: DateTime.utc_now()
      )

    link(connection, organization, admin)

    stub(Hexpm.Billing.Mock, :get, fn _token, _opts -> %{"quantity" => 5} end)

    %{
      organization: organization,
      repository: repository,
      package: package,
      admin: admin,
      member: member,
      connection: connection
    }
  end

  describe "private package pages" do
    test "send a governed member at their provider", context do
      require_sso(context)
      {conn, _session} = login(context.member)

      conn = get(conn, "/packages/#{context.repository.name}/#{context.package.name}")

      assert redirected_to(conn) ==
               "/sso/org/#{context.organization.name}?return=" <>
                 URI.encode_www_form(
                   "/packages/#{context.repository.name}/#{context.package.name}"
                 )
    end

    test "serve once the member has authenticated on that browser session", context do
      require_sso(context)
      {conn, session} = login(context.member)
      authenticate(context, context.member, session)

      conn = get(conn, "/packages/#{context.repository.name}/#{context.package.name}")

      assert response(conn, 200) =~ context.package.name
    end

    test "are untouched while the organization only pilots", context do
      {conn, _session} = login(context.member)

      conn = get(conn, "/packages/#{context.repository.name}/#{context.package.name}")

      assert response(conn, 200) =~ context.package.name
    end

    test "stay missing for someone who is not a member", context do
      require_sso(context)
      {conn, _session} = login(insert(:user))

      conn = get(conn, "/packages/#{context.repository.name}/#{context.package.name}")

      assert response(conn, 404)
    end

    test "send a governed member off the file browser too", context do
      require_sso(context)
      {conn, _session} = login(context.member)

      path = "/packages/#{context.repository.name}/#{context.package.name}/1.0.0/files"
      conn = get(conn, path)

      assert redirected_to(conn) ==
               "/sso/org/#{context.organization.name}?return=" <> URI.encode_www_form(path)
    end

    test "send a governed member off the diff view too", context do
      require_sso(context)
      insert(:release, package: context.package, version: "2.0.0")
      {conn, _session} = login(context.member)

      conn =
        get(conn, "/diff/#{context.repository.name}/#{context.package.name}/1.0.0..2.0.0")

      assert redirected_to(conn) =~ "/sso/org/#{context.organization.name}?return="
    end

    test "leave the public repository alone", context do
      require_sso(context)
      public = insert(:package)
      insert(:release, package: public, version: "1.0.0")
      {conn, _session} = login(context.member)

      assert response(get(conn, "/packages/#{public.name}"), 200)
    end
  end

  describe "the dashboard" do
    test "refuses a governed admin", context do
      require_sso(context)
      {conn, _session} = login(context.admin)

      conn = get(conn, "/dashboard/orgs/#{context.organization.name}/members")

      assert redirected_to(conn) =~ "/sso/org/#{context.organization.name}"
    end

    test "admits them once they have authenticated", context do
      require_sso(context)
      {conn, session} = login(context.admin)
      authenticate(context, context.admin, session)

      conn = get(conn, "/dashboard/orgs/#{context.organization.name}/members")

      assert response(conn, 200)
    end

    test "keeps billing reachable and says so", context do
      require_sso(context)
      {conn, _session} = login(context.admin)

      conn = get(conn, "/dashboard/orgs/#{context.organization.name}/billing")

      assert response(conn, 200)

      assert [log] = break_glass_logs(context)
      assert log.params["screen"] == "billing"
      assert log.user_id == context.admin.id
    end

    test "keeps the SSO settings reachable", context do
      require_sso(context)
      {conn, _session} = login(context.admin)

      conn = get(conn, "/dashboard/orgs/#{context.organization.name}/sso")

      assert response(conn, 200)
      assert [_log] = break_glass_logs(context)
    end

    test "records one break-glass and one notice however many pages are opened", context do
      require_sso(context)

      for _ <- 1..3 do
        {conn, _session} = login(context.admin)
        assert response(get(conn, "/dashboard/orgs/#{context.organization.name}/billing"), 200)
      end

      assert [_log] = break_glass_logs(context)

      assert [_entry] =
               Repo.all(from(e in OutboxEntry, where: e.category == "sso.break_glass"))
    end

    test "records nothing while the admin has a session", context do
      require_sso(context)
      {conn, session} = login(context.admin)
      authenticate(context, context.admin, session)

      assert response(get(conn, "/dashboard/orgs/#{context.organization.name}/billing"), 200)

      assert break_glass_logs(context) == []
    end
  end

  describe "the organization API" do
    test "refuses a personal key and names a credential that works", context do
      require_sso(context)

      conn =
        build_conn()
        |> put_req_header("authorization", key_for(context.member))
        |> get("/api/orgs/#{context.organization.name}")

      assert json_response(conn, 403)["message"] =~ "does not accept personal API keys"
      assert json_response(conn, 403)["message"] =~ "organization key"
    end

    test "refuses basic auth, which holds no session either", context do
      require_sso(context)
      user = insert(:user, password: Hexpm.Accounts.Auth.gen_password("hunter42"))
      insert(:organization_user, organization: context.organization, user: user, role: "read")

      conn =
        build_conn()
        |> put_req_header("authorization", basic_auth(user.username, "hunter42"))
        |> get("/api/orgs/#{context.organization.name}")

      assert json_response(conn, 403)["message"] =~ "requires authenticating through its identity"
    end

    test "lets a personal key through where the organization allows them", context do
      require_sso(context, "allow")

      conn =
        build_conn()
        |> put_req_header("authorization", key_for(context.member))
        |> get("/api/orgs/#{context.organization.name}")

      assert json_response(conn, 200)["name"] == context.organization.name
    end

    test "never governs the organization's own key", context do
      require_sso(context)

      conn =
        build_conn()
        |> put_req_header("authorization", key_for(context.organization))
        |> get("/api/orgs/#{context.organization.name}")

      assert json_response(conn, 200)["name"] == context.organization.name
    end
  end

  describe "publishing" do
    test "refuses a personal key", context do
      require_sso(context)

      meta = %{name: context.package.name, version: "2.0.0", description: "New"}

      conn =
        build_conn()
        |> put_req_header("content-type", "application/octet-stream")
        |> put_req_header("authorization", key_for(context.member, api_write()))
        |> post("/api/publish?repository=#{context.repository.name}", create_tar(meta))

      assert json_response(conn, 403)["message"] =~ "does not accept personal API keys"
    end

    test "lets the organization's own key through", context do
      require_sso(context)

      meta = %{name: context.package.name, version: "2.0.0", description: "New"}

      conn =
        build_conn()
        |> put_req_header("content-type", "application/octet-stream")
        |> put_req_header("authorization", key_for(context.organization, api_write()))
        |> post("/api/publish?repository=#{context.repository.name}", create_tar(meta))

      assert json_response(conn, 201)["version"] == "2.0.0"
    end

    test "refuses an OAuth token with no organization access session", context do
      require_sso(context)
      member = enable_tfa(context.member)
      token = oauth_token(member, ["api:write"])

      meta = %{name: context.package.name, version: "2.0.0", description: "New"}

      conn =
        build_conn()
        |> put_req_header("content-type", "application/octet-stream")
        |> put_req_header("authorization", "Bearer #{token.access_token}")
        |> put_req_header("x-hex-otp", otp(member))
        |> post("/api/publish?repository=#{context.repository.name}", create_tar(meta))

      assert json_response(conn, 403)["message"] =~ "requires authenticating through its identity"
    end

    test "lets an OAuth token whose session is authenticated through", context do
      require_sso(context)
      member = enable_tfa(context.member)
      token = oauth_token(member, ["api:write"])
      authenticate(context, member, %{id: token.user_session_id})

      meta = %{name: context.package.name, version: "2.0.0", description: "New"}

      conn =
        build_conn()
        |> put_req_header("content-type", "application/octet-stream")
        |> put_req_header("authorization", "Bearer #{token.access_token}")
        |> put_req_header("x-hex-otp", otp(member))
        |> post("/api/publish?repository=#{context.repository.name}", create_tar(meta))

      assert json_response(conn, 201)["version"] == "2.0.0"
    end
  end

  describe "the edge check at /api/auth" do
    test "refuses a personal key the day enforcement starts, before any sweep", context do
      secret = key_for(context.member, repository_permission(context))
      require_sso(context)

      conn =
        build_conn()
        |> put_req_header("authorization", secret)
        |> get("/api/auth", domain: "repository", resource: context.organization.name)

      assert json_response(conn, 403)["message"] =~ "does not accept personal API keys"
    end

    test "lets the organization's own key through", context do
      require_sso(context)
      secret = key_for(context.organization, repository_permission(context))

      conn =
        build_conn()
        |> put_req_header("authorization", secret)
        |> get("/api/auth", domain: "repository", resource: context.organization.name)

      assert json_response(conn, 200)["key"]["owner"]["type"] == "organization"
    end

    test "leaves an OAuth token to its scopes", context do
      require_sso(context)
      token = oauth_token(context.member, ["api:read", "repository:#{context.organization.name}"])

      # The scope is minted against a live organization access session when the
      # token is refreshed, so this endpoint does not decide it a second time.
      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token.access_token}")
        |> get("/api/auth", domain: "repository", resource: context.organization.name)

      assert response(conn, 204)
    end
  end

  describe "creating a personal key" do
    test "is refused for every shape that reaches a blocking organization", context do
      require_sso(context)

      shapes = [
        %{"domain" => "repository", "resource" => context.organization.name},
        %{"domain" => "docs", "resource" => context.organization.name},
        %{
          "domain" => "package",
          "resource" => "#{context.organization.name}/#{context.package.name}"
        },
        %{"domain" => "repositories"}
      ]

      for shape <- shapes do
        assert {:error, :key, changeset, _} =
                 Hexpm.Accounts.Keys.create(
                   context.member,
                   %{name: "k-#{System.unique_integer([:positive])}", permissions: [shape]},
                   audit: audit_data(context.member)
                 )

        assert %{resource: message} =
                 HexpmWeb.ControllerHelpers.translate_errors(changeset).permissions

        assert message =~ "does not accept personal API keys"
      end
    end

    test "is allowed where the organization allows personal keys", context do
      require_sso(context, "allow")

      assert {:ok, %{key: _key}} =
               Hexpm.Accounts.Keys.create(
                 context.member,
                 %{
                   name: "allowed",
                   permissions: [
                     %{"domain" => "repository", "resource" => context.organization.name}
                   ]
                 },
                 audit: audit_data(context.member)
               )
    end

    test "leaves an unrelated organization alone", context do
      require_sso(context)
      other = insert(:organization)
      insert(:organization_user, organization: other, user: context.member, role: "write")

      assert {:ok, %{key: _key}} =
               Hexpm.Accounts.Keys.create(
                 context.member,
                 %{
                   name: "other",
                   permissions: [%{"domain" => "repository", "resource" => other.name}]
                 },
                 audit: audit_data(context.member)
               )
    end

    test "leaves the organization's own keys alone", context do
      require_sso(context)

      assert {:ok, %{key: _key}} =
               Hexpm.Accounts.Keys.create(
                 context.organization,
                 %{
                   name: "ci",
                   permissions: [
                     %{"domain" => "repository", "resource" => context.organization.name}
                   ]
                 },
                 audit: audit_data(context.admin)
               )
    end
  end

  defp require_sso(context, personal_keys \\ "block") do
    {:ok, connection} =
      SSO.configure_enforcement(
        context.organization,
        %{"enforcement_mode" => "required", "personal_keys" => personal_keys},
        audit: audit_data(context.admin)
      )

    connection
  end

  defp login(user) do
    {:ok, session, token} =
      Hexpm.UserSessions.create_browser_session(user,
        name: "Test Browser Session",
        audit: test_audit_data(user)
      )

    conn =
      Plug.Test.init_test_session(build_conn(), %{
        "session_token" => Base.encode64(token),
        "sudo_authenticated_at" => NaiveDateTime.to_iso8601(NaiveDateTime.utc_now())
      })

    {conn, session}
  end

  defp authenticate(context, user, session) do
    identity =
      Repo.get_by(Hexpm.Accounts.SSO.Identity,
        connection_id: context.connection.id,
        user_id: user.id
      ) || link(context.connection, context.organization, user)

    SSO.establish_org_session!(identity, session.id)
  end

  defp link(connection, organization, user, subject \\ nil) do
    insert(:organization_sso_identity,
      connection: connection,
      organization: organization,
      user: user,
      subject: subject || "sub-#{user.id}"
    )
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
        "test_grant_ref",
        user_session_id: session.id
      )

    token
  end

  defp api_write, do: [%{domain: "api", resource: "write"}]

  defp enable_tfa(user) do
    user
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.put_embed(:tfa, %Hexpm.Accounts.TFA{
      secret: Hexpm.Accounts.TFA.generate_secret()
    })
    |> Repo.update!()
  end

  defp otp(user), do: Hexpm.Accounts.TFA.time_based_token(user.tfa.secret)

  defp repository_permission(context) do
    [%{domain: "repository", resource: context.organization.name}]
  end

  defp basic_auth(username, password) do
    "Basic " <> Base.encode64("#{username}:#{password}")
  end

  defp break_glass_logs(context) do
    Hexpm.Accounts.AuditLogs.all_by(context.organization)
    |> Enum.filter(&(&1.action == "sso.break_glass"))
  end
end
