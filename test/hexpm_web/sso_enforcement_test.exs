defmodule HexpmWeb.SSOEnforcementTest do
  use HexpmWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Hexpm.Accounts.SSO
  alias Hexpm.Accounts.SSO.Enforcement
  alias Hexpm.Diff.Cache
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

    test "send a governed full owner off the owners page too", context do
      insert(:package_owner, package: context.package, user: context.member, level: "full")
      require_sso(context)
      {conn, _session} = login(context.member)

      path = "/packages/#{context.repository.name}/#{context.package.name}/owners"
      conn = get(conn, path)

      assert redirected_to(conn) ==
               "/sso/org/#{context.organization.name}?return=" <> URI.encode_www_form(path)
    end

    test "leave the public repository alone", context do
      require_sso(context)
      public = insert(:package)
      insert(:release, package: public, version: "1.0.0")
      {conn, _session} = login(context.member)

      assert response(get(conn, "/packages/#{public.name}"), 200)
    end
  end

  describe "a connected LiveView" do
    test "re-resolves the repositories a search reaches", context do
      require_sso(context)
      {conn, session} = login(context.member)
      authenticate(context, context.member, session)

      {:ok, view, html} = live(conn, "/packages?search=#{context.package.name}")

      assert html =~ "#{context.repository.name}/#{context.package.name}"

      expire_org_sessions(session)

      refute render_patch(view, "/packages?search=#{context.package.name}&sort=name") =~
               "#{context.repository.name}/#{context.package.name}"
    end

    test "sends the diff view at the provider before loading another piece", context do
      require_sso(context)
      insert(:release, package: context.package, version: "2.0.0")
      {conn, session} = login(context.member)
      authenticate(context, context.member, session)

      {:ok, request} =
        Hexpm.Diff.prepare(context.repository.name, context.package.name, "1.0.0", "2.0.0", [])

      put_ready_cache(request, 6)

      path = "/diff/#{context.repository.name}/#{context.package.name}/1.0.0..2.0.0"
      {:ok, view, html} = live(conn, path)

      assert html =~ "5 of 6 files loaded"
      assert html =~ ~s(id="diff-gap-5-5")

      expire_org_sessions(session)

      assert {:error, {:redirect, %{to: to}}} =
               render_hook(view, "load-gap", %{"start" => "5", "last" => "5"})

      assert to == "/sso/org/#{context.organization.name}?return=" <> URI.encode_www_form(path)
    end

    test "refuses a package report filed after the session lapses", context do
      require_sso(context)
      {conn, session} = login(context.member)
      authenticate(context, context.member, session)

      path = "/packages/#{context.repository.name}/#{context.package.name}/report"
      {:ok, view, _html} = live(conn, path)

      expire_org_sessions(session)

      assert {:error, {:redirect, %{to: to}}} =
               render_submit(view, "submit", %{
                 "h-captcha-response" => "captcha",
                 "report" => %{
                   reason: "other",
                   summary: "Question",
                   description: "Report details"
                 }
               })

      assert to == "/sso/org/#{context.organization.name}?return=" <> URI.encode_www_form(path)
      refute Repo.exists?(Hexpm.PackageReports.Report)
    end

    test "drops the organization of a member removed while the search is open", context do
      {conn, _session} = login(context.member)

      {:ok, view, html} = live(conn, "/packages?search=#{context.package.name}")

      assert html =~ "#{context.repository.name}/#{context.package.name}"

      remove_member(context, context.member)

      refute render_patch(view, "/packages?search=#{context.package.name}&sort=name") =~
               "#{context.repository.name}/#{context.package.name}"
    end

    test "stops feeding the diff view to a member removed while it is open", context do
      insert(:release, package: context.package, version: "2.0.0")
      {conn, _session} = login(context.member)

      {:ok, request} =
        Hexpm.Diff.prepare(context.repository.name, context.package.name, "1.0.0", "2.0.0", [])

      put_ready_cache(request, 6)

      path = "/diff/#{context.repository.name}/#{context.package.name}/1.0.0..2.0.0"
      {:ok, view, html} = live(conn, path)

      assert html =~ "5 of 6 files loaded"

      remove_member(context, context.member)

      assert render_hook(view, "load-gap", %{"start" => "5", "last" => "5"}) =~
               "Package not found"
    end

    test "drops the organization once the session behind the socket is revoked", context do
      {conn, session} = login(context.member)

      {:ok, view, html} = live(conn, "/packages?search=#{context.package.name}")

      assert html =~ "#{context.repository.name}/#{context.package.name}"

      {:ok, _session} = Hexpm.UserSessions.revoke(session)

      refute render_patch(view, "/packages?search=#{context.package.name}&sort=name") =~
               "#{context.repository.name}/#{context.package.name}"
    end

    test "stops feeding the diff view once the session behind the socket is revoked", context do
      insert(:release, package: context.package, version: "2.0.0")
      {conn, session} = login(context.member)

      {:ok, request} =
        Hexpm.Diff.prepare(context.repository.name, context.package.name, "1.0.0", "2.0.0", [])

      put_ready_cache(request, 6)

      path = "/diff/#{context.repository.name}/#{context.package.name}/1.0.0..2.0.0"
      {:ok, view, html} = live(conn, path)

      assert html =~ "5 of 6 files loaded"

      {:ok, _session} = Hexpm.UserSessions.revoke(session)

      assert render_hook(view, "load-gap", %{"start" => "5", "last" => "5"}) =~
               "Package not found"
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

      # The per-member enforcement control is what the members tab derives from
      # the mode, and it only appears once the organization is not optional.
      assert response(conn, 200) =~ "sso-enforcement-form-#{context.member.id}"
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

    test "records every break-glass and notifies once however many pages are opened", context do
      require_sso(context)

      for _ <- 1..3 do
        {conn, _session} = login(context.admin)
        assert response(get(conn, "/dashboard/orgs/#{context.organization.name}/billing"), 200)
      end

      # The audit entry is the only record that an action was taken without a
      # session, so suppressing the later ones would make a sequence of repairs
      # read like an administrator who authenticated normally.
      assert length(break_glass_logs(context)) == 3

      assert [_entry] =
               Repo.all(from(e in OutboxEntry, where: e.category == "sso.break_glass"))
    end

    test "keeps leaving the organization reachable", context do
      require_sso(context)
      {conn, _session} = login(context.member)

      conn =
        post(conn, "/dashboard/orgs/#{context.organization.name}/leave", %{
          "organization_name" => context.organization.name
        })

      assert redirected_to(conn) == "/dashboard/profile"
    end

    # Leaving is carved out because it is the only lever someone deactivated at
    # the provider has, and it is worth nothing if the only page carrying the
    # form is gated.
    test "keeps the page carrying the leave form reachable", context do
      require_sso(context)
      {conn, _session} = login(context.member)

      conn = get(conn, "/dashboard/orgs/#{context.organization.name}/danger-zone")

      assert response(conn, 200) =~ "/dashboard/orgs/#{context.organization.name}/leave"
    end

    # The provider sends the browser back with a GET, so replaying a POST path
    # either 404s or loads the page and says the action succeeded when nothing
    # ran.
    test "sends a refused POST back to the page it came from", context do
      require_sso(context)
      {conn, _session} = login(context.admin)
      members_path = "/dashboard/orgs/#{context.organization.name}/members"

      conn =
        conn
        |> put_req_header("referer", "http://localhost:5000" <> members_path)
        |> post("/dashboard/orgs/#{context.organization.name}", %{
          "action" => "add_member",
          "organization_user" => %{"username" => context.member.username, "role" => "read"}
        })

      assert redirected_to(conn) ==
               "/sso/org/#{context.organization.name}?return=" <>
                 URI.encode_www_form(members_path)
    end

    test "sends a refused POST with no referer at the provider with nowhere to return",
         context do
      require_sso(context)
      {conn, _session} = login(context.admin)

      conn =
        post(conn, "/dashboard/orgs/#{context.organization.name}", %{
          "action" => "add_member",
          "organization_user" => %{"username" => context.member.username, "role" => "read"}
        })

      assert redirected_to(conn) == "/sso/org/#{context.organization.name}"
    end

    test "takes a fresh password before replacing the provider", context do
      require_sso(context)

      # Inside the rolling sudo window that login grants, outside the short one
      # the destructive actions ask for.
      {conn, _session} = login(context.admin, sudo_at: minutes_ago(5))

      assert conn
             |> post("/dashboard/orgs/#{context.organization.name}/sso/disable", %{})
             |> redirected_to() =~ "/sudo"

      # The reachable-while-locked-out screens still open on the same session.
      assert response(get(conn, "/dashboard/orgs/#{context.organization.name}/billing"), 200)
    end

    test "accounts for the billing proxy the same way the billing screen is", context do
      require_sso(context)
      {conn, _session} = login(context.admin)

      stub(Hexpm.HTTP.Mock, :post, fn _url, _headers, _body, _opts ->
        {:ok, 200, [], %{"client_secret" => "seti_123"}}
      end)

      conn =
        post(
          conn,
          "/dashboard/billing-api/api/customers/#{context.organization.name}/setup_intent"
        )

      assert json_response(conn, 200)

      assert [log] = break_glass_logs(context)
      assert log.params["screen"] == "billing"
      assert log.user_id == context.admin.id
    end

    test "records nothing for a billing-proxy path that reaches no action", context do
      require_sso(context)
      {conn, _session} = login(context.admin)

      conn =
        post(conn, "/dashboard/billing-api/api/customers/#{context.organization.name}/nonsense")

      assert json_response(conn, 404)
      assert break_glass_logs(context) == []
    end

    test "records nothing for a member the billing proxy turns away", context do
      require_sso(context)
      {conn, _session} = login(context.member)

      conn =
        post(
          conn,
          "/dashboard/billing-api/api/customers/#{context.organization.name}/setup_intent"
        )

      assert json_response(conn, 403)
      assert break_glass_logs(context) == []
    end

    test "records nothing for a member the billing screen turns away", context do
      require_sso(context)
      {conn, _session} = login(context.member)

      conn = get(conn, "/dashboard/orgs/#{context.organization.name}/billing")

      assert response(conn, 400)
      assert break_glass_logs(context) == []
    end

    # Every SSO configuration action is carved out, so refusing a non-admin with
    # a redirect would let them write these rows at will and mail the admins
    # about actions they never ran.
    test "records nothing for a member the SSO configuration turns away", context do
      require_sso(context)
      {conn, _session} = login(context.member)

      conn =
        post(conn, "/dashboard/orgs/#{context.organization.name}/sso/jit", %{
          "jit" => %{"jit_seat_policy" => "block", "jit_role" => "read"}
        })

      assert response(conn, 403)
      assert break_glass_logs(context) == []
    end

    test "names the screen that was reached in the audit log", context do
      require_sso(context)
      {conn, session} = login(context.admin)

      assert response(get(conn, "/dashboard/orgs/#{context.organization.name}/billing"), 200)

      authenticate(context, context.admin, session)

      html =
        conn
        |> get("/dashboard/orgs/#{context.organization.name}/audit-logs")
        |> response(200)

      assert html =~ "Reached #{context.organization.name}&#39;s billing without a current"
    end

    test "records nothing while the admin has a session", context do
      require_sso(context)
      {conn, session} = login(context.admin)
      authenticate(context, context.admin, session)

      assert response(get(conn, "/dashboard/orgs/#{context.organization.name}/billing"), 200)

      assert break_glass_logs(context) == []
    end

    test "says so rather than falling over on an enforcement change it cannot make", context do
      require_sso(context)
      {conn, session} = login(context.admin)
      authenticate(context, context.admin, session)
      path = "/dashboard/orgs/#{context.organization.name}/sso/enforcement/member"

      outsider =
        post(conn, path, %{"user_id" => insert(:user).id, "sso_enforcement" => "exempt"})

      assert Phoenix.Flash.get(outsider.assigns.flash, :error) =~ "not a member"

      nonsense =
        post(conn, path, %{"user_id" => context.member.id, "sso_enforcement" => "maybe"})

      assert Phoenix.Flash.get(nonsense.assigns.flash, :error) =~ "not an enforcement setting"
    end

    test "does not reach into exempting a member", context do
      require_sso(context)
      {conn, _session} = login(context.admin)

      conn =
        post(conn, "/dashboard/orgs/#{context.organization.name}/sso/enforcement/member", %{
          "user_id" => context.admin.id,
          "sso_enforcement" => "exempt"
        })

      assert redirected_to(conn) =~ "/sso/org/#{context.organization.name}"

      assert Repo.get_by!(Hexpm.Accounts.OrganizationUser,
               organization_id: context.organization.id,
               user_id: context.admin.id
             ).sso_enforcement == nil
    end

    test "still turns enforcement off for the whole organization", context do
      require_sso(context)
      {conn, _session} = login(context.admin)

      conn =
        post(conn, "/dashboard/orgs/#{context.organization.name}/sso/enforcement", %{
          "enforcement" => %{"enforcement_mode" => "optional"}
        })

      assert redirected_to(conn) == "/dashboard/orgs/#{context.organization.name}/sso"

      assert Repo.get!(Hexpm.Accounts.SSO.Connection, context.connection.id).enforcement_mode ==
               "optional"
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

      message = json_response(conn, 403)["message"]

      assert message =~ "requires authenticating through its identity"
      assert message =~ "username and password"
      refute message =~ "/sso/org/"
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

    test "never governs a token minted from the organization's own key", context do
      require_sso(context)

      secret =
        key_for(context.organization, [
          %{"domain" => "api", "resource" => "read"},
          %{"domain" => "repositories"}
        ])

      body = client_credentials(secret, "api:read repositories")

      assert body["scope"] =~ "repository:#{context.organization.name}"

      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{body["access_token"]}")
        |> get("/api/orgs/#{context.organization.name}")

      # The subject is the organization rather than a person, so nothing about
      # it is governed and no organization access session is looked for.
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

      message = json_response(conn, 403)["message"]

      assert message =~ "requires authenticating through its identity"
      assert message =~ "authenticate this session again from your Hex client"
      refute message =~ "mix hex"

      # A sign-in URL would authenticate the browser that followed it, not this
      # token's session, so the refusal must not offer one.
      refute message =~ "/sso/org/"
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

  describe "a public package the organization owns" do
    setup context do
      package = insert(:package, repository_id: 1)
      insert(:release, package: package, version: "1.0.0")
      insert(:package_owner, package: package, user: context.organization.user, level: "full")

      %{public_package: package}
    end

    test "refuses a release from a session with no organization access", context do
      require_sso(context)
      member = enable_tfa(context.member)
      token = oauth_token(member, ["api:write"])

      meta = %{name: context.public_package.name, version: "2.0.0", description: "New"}

      conn =
        build_conn()
        |> put_req_header("content-type", "application/octet-stream")
        |> put_req_header("authorization", "Bearer #{token.access_token}")
        |> put_req_header("x-hex-otp", otp(member))
        |> post("/api/publish", create_tar(meta))

      assert json_response(conn, 403)["message"] =~ "requires authenticating through its identity"
    end

    test "publishes once that session has authenticated", context do
      require_sso(context)
      member = enable_tfa(context.member)
      session = oauth_session(member)
      authenticate(context, member, session)
      token = oauth_token(member, ["api:write"], session)

      meta = %{name: context.public_package.name, version: "2.0.0", description: "New"}

      conn =
        build_conn()
        |> put_req_header("content-type", "application/octet-stream")
        |> put_req_header("authorization", "Bearer #{token.access_token}")
        |> put_req_header("x-hex-otp", otp(member))
        |> post("/api/publish", create_tar(meta))

      assert json_response(conn, 201)["version"] == "2.0.0"
    end

    test "refuses a personal key the organization turns away", context do
      require_sso(context)

      meta = %{name: context.public_package.name, version: "2.0.0", description: "New"}

      conn =
        build_conn()
        |> put_req_header("content-type", "application/octet-stream")
        |> put_req_header("authorization", key_for(context.member, api_write()))
        |> post("/api/publish", create_tar(meta))

      assert json_response(conn, 403)["message"] =~ "does not accept personal API keys"
    end

    test "refuses an owner change from a session with no organization access", context do
      require_sso(context)
      admin = enable_tfa(context.admin)
      token = oauth_token(admin, ["api:write"])
      other = insert(:user, emails: [build(:email, verified: true, primary: true)])

      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token.access_token}")
        |> put_req_header("x-hex-otp", otp(admin))
        |> put("/api/packages/#{context.public_package.name}/owners/#{hd(other.emails).email}")

      assert json_response(conn, 403)["message"] =~ "requires authenticating through its identity"
    end

    # Ownership here comes from the organization rather than from a package
    # owner row of the member's own, which is what enforcement is about: the
    # package lives in the public repository, so its repository's organization
    # is the public one and never governed.
    test "sends a governed administrator off the owners page", context do
      require_sso(context)
      {conn, _session} = login(context.admin)

      path = "/packages/#{context.public_package.name}/owners"
      conn = get(conn, path)

      assert redirected_to(conn) ==
               "/sso/org/#{context.organization.name}?return=" <> URI.encode_www_form(path)
    end

    test "lets an administrator who has authenticated onto the owners page", context do
      require_sso(context)
      {conn, session} = login(context.admin)
      authenticate(context, context.admin, session)

      conn = get(conn, "/packages/#{context.public_package.name}/owners")

      assert html_response(conn, 200) =~ "Current owners"
    end

    test "refuses the package domain at /api/auth for a governed member", context do
      require_sso(context)
      token = oauth_token(context.member, ["api:write"])

      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token.access_token}")
        |> get("/api/auth", domain: "package", resource: "hexpm/#{context.public_package.name}")

      assert json_response(conn, 403)["message"] =~ "requires authenticating through its identity"
    end

    test "answers the package domain at /api/auth once that session has authenticated",
         context do
      require_sso(context)
      session = oauth_session(context.member)
      authenticate(context, context.member, session)
      token = oauth_token(context.member, ["api:write"], session)

      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token.access_token}")
        |> get("/api/auth", domain: "package", resource: "hexpm/#{context.public_package.name}")

      assert response(conn, 204)
    end

    test "refuses retiring a release from a session with no organization access", context do
      require_sso(context)
      member = enable_tfa(context.member)
      token = oauth_token(member, ["api:write"])

      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token.access_token}")
        |> put_req_header("x-hex-otp", otp(member))
        |> post("/api/packages/#{context.public_package.name}/releases/1.0.0/retire", %{
          "reason" => "security",
          "message" => "CVE"
        })

      assert json_response(conn, 403)["message"] =~ "requires authenticating through its identity"
    end

    test "leaves a public package no organization owns alone", context do
      require_sso(context)
      member = enable_tfa(context.member)
      token = oauth_token(member, ["api:write"])
      package = insert(:package, repository_id: 1)
      insert(:release, package: package, version: "1.0.0")
      insert(:package_owner, package: package, user: member, level: "full")

      meta = %{name: package.name, version: "2.0.0", description: "New"}

      conn =
        build_conn()
        |> put_req_header("content-type", "application/octet-stream")
        |> put_req_header("authorization", "Bearer #{token.access_token}")
        |> put_req_header("x-hex-otp", otp(member))
        |> post("/api/publish", create_tar(meta))

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

    test "resolves a package to its organization for both checks", context do
      require_sso(context)
      token = oauth_token(context.member, ["api"])

      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token.access_token}")
        |> get("/api/auth",
          domain: "package",
          resource: "#{context.organization.name}/#{context.package.name}"
        )

      # A bare api scope satisfies the package domain, so nothing has filtered
      # this token against an organization access session and this endpoint
      # takes the decision itself.
      assert json_response(conn, 403)["message"] =~ "requires authenticating through its identity"
    end

    test "resolves a package for a governed session that has authenticated", context do
      require_sso(context)
      session = oauth_session(context.member)
      authenticate(context, context.member, session)
      token = oauth_token(context.member, ["api"], session)

      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token.access_token}")
        |> get("/api/auth",
          domain: "package",
          resource: "#{context.organization.name}/#{context.package.name}"
        )

      assert response(conn, 204)
    end

    test "leaves an OAuth token to its scopes", context do
      require_sso(context)
      session = oauth_session(context.member)
      authenticate(context, context.member, session)

      token =
        oauth_token(
          context.member,
          ["api:read", "repository:#{context.organization.name}"],
          session
        )

      # The scope was minted against a live organization access session, so this
      # endpoint does not decide it a second time.
      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token.access_token}")
        |> get("/api/auth", domain: "repository", resource: context.organization.name)

      assert response(conn, 204)
    end
  end

  describe "OAuth scopes" do
    test "carry the organizations the session has authenticated for", context do
      require_sso(context)
      session = oauth_session(context.member)
      authenticate(context, context.member, session)

      token = oauth_token(context.member, ["api:read", "repositories"], session)

      assert "repository:#{context.organization.name}" in token.scopes
      assert token.sso_reauth_required == []
    end

    test "drop the ones it has not, and name them", context do
      require_sso(context)

      token = oauth_token(context.member, ["api:read", "repositories"])

      refute "repository:#{context.organization.name}" in token.scopes
      assert token.sso_reauth_required == [context.organization.name]
    end

    test "drop a docs scope the same way a repository scope goes", context do
      require_sso(context)
      name = context.organization.name

      token = oauth_token(context.member, ["api:read", "docs:#{name}", "repository:#{name}"])

      assert token.scopes == ["api:read"]
      assert token.sso_reauth_required == [name]
    end

    test "are unaffected while the organization does not enforce", context do
      token = oauth_token(context.member, ["api:read", "repositories"])

      assert "repository:#{context.organization.name}" in token.scopes
      assert token.sso_reauth_required == []
    end

    test "are re-derived on refresh, and the flag reaches the client", context do
      require_sso(context)
      session = oauth_session(context.member)
      authenticate(context, context.member, session)

      token = oauth_token(context.member, ["api:read", "repositories"], session)
      assert "repository:#{context.organization.name}" in token.scopes

      expire_org_sessions(session)
      body = refresh(token, session)

      refute body["scope"] =~ "repository:#{context.organization.name}"
      assert body["sso_reauth_required"] == [context.organization.name]
    end

    test "leave an organization the member was removed from unnamed", context do
      require_sso(context)
      session = oauth_session(context.member)
      authenticate(context, context.member, session)

      token = oauth_token(context.member, ["api:read", "repositories"], session)
      assert "repository:#{context.organization.name}" in token.scopes

      Repo.delete_all(
        from(m in Hexpm.Accounts.OrganizationUser, where: m.user_id == ^context.member.id)
      )

      body = refresh(token, session)

      # Dropped, like a lapsed session, but not named: authenticating would not
      # give it back and the client has nothing to act on.
      refute body["scope"] =~ "repository:#{context.organization.name}"
      refute Map.has_key?(body, "sso_reauth_required")
    end

    test "say nothing to a client that has nothing to fix", context do
      session = oauth_session(context.member)
      token = oauth_token(context.member, ["api:read"], session)

      refute Map.has_key?(refresh(token, session), "sso_reauth_required")
    end
  end

  describe "authorizing a client" do
    test "carries the browser's organization access onto the new session", context do
      require_sso(context)
      {_conn, browser} = login(context.member)
      authenticate(context, context.member, browser)

      oauth = oauth_session(context.member)
      SSO.grant_org_sessions!(browser.id, oauth.id, context.member.id)

      assert Enforcement.check(context.organization, context.member, nil, oauth.id) == :ok
    end

    test "does not restart the clock the administrator set", context do
      require_sso(context)
      {_conn, browser} = login(context.member)
      source = authenticate(context, context.member, browser)

      oauth = oauth_session(context.member)
      assert [granted] = SSO.grant_org_sessions!(browser.id, oauth.id, context.member.id)

      assert DateTime.compare(granted.expires_at, source.expires_at) == :eq
    end

    test "a second flow leaves the first session's access alone", context do
      require_sso(context)
      {first_conn, first_browser} = login(context.member)
      authenticate(context, context.member, first_browser)

      first_oauth = oauth_session(context.member)

      assert [_granted] =
               SSO.grant_org_sessions!(first_browser.id, first_oauth.id, context.member.id)

      {_second_conn, second_browser} = login(context.member)
      authenticate(context, context.member, second_browser)
      second_oauth = oauth_session(context.member)
      SSO.grant_org_sessions!(second_browser.id, second_oauth.id, context.member.id)

      assert Enforcement.check(context.organization, context.member, nil, first_oauth.id) == :ok
      assert Enforcement.check(context.organization, context.member, nil, second_oauth.id) == :ok

      assert response(
               get(first_conn, "/packages/#{context.repository.name}/#{context.package.name}"),
               200
             ) =~ context.package.name
    end

    test "carries nothing when the browser had nothing", context do
      require_sso(context)
      {_conn, browser} = login(context.member)
      oauth = oauth_session(context.member)

      assert SSO.grant_org_sessions!(browser.id, oauth.id, context.member.id) == []
    end

    test "a device approved in an authenticated browser starts out authenticated", context do
      require_sso(context)
      {conn, browser} = login(context.member)
      authenticate(context, context.member, browser)

      client = insert(:oauth_client)

      {:ok, response} =
        Hexpm.OAuth.DeviceCodes.initiate_device_authorization(
          build_conn(),
          client.client_id,
          ["api:read", "repositories"]
        )

      conn =
        conn
        |> Plug.Conn.put_session("device_code_verified", %{
          "user_code" => response.user_code,
          "verified_at" => NaiveDateTime.to_iso8601(NaiveDateTime.utc_now())
        })
        |> post("/oauth/device/authorize", %{
          "action" => "authorize",
          "selected_scopes" => ["api:read", "repositories"]
        })

      assert redirected_to(conn) == "/"

      body =
        build_conn()
        |> post("/api/oauth/token", %{
          "grant_type" => "urn:ietf:params:oauth:grant-type:device_code",
          "device_code" => response.device_code,
          "client_id" => client.client_id
        })
        |> json_response(200)

      assert body["scope"] =~ "repository:#{context.organization.name}"
      refute Map.has_key?(body, "sso_reauth_required")
    end

    # The flow hexdocs uses, and the one that carries a docs scope rather than
    # the CLI's repositories.
    test "a client consented to in an authenticated browser starts out authenticated", context do
      require_sso(context)
      {conn, browser} = login(context.member)
      authenticate(context, context.member, browser)

      name = context.organization.name
      client = insert(:oauth_client, allowed_scopes: ["api:read", "docs"])
      verifier = "code-verifier-#{System.unique_integer([:positive])}"
      challenge = :sha256 |> :crypto.hash(verifier) |> Base.url_encode64(padding: false)

      conn =
        post(conn, "/oauth/authorize", %{
          "client_id" => client.client_id,
          "redirect_uri" => hd(client.redirect_uris),
          "action" => "approve",
          "scope" => "docs:#{name}",
          "selected_scopes" => ["docs:#{name}"],
          "state" => "opaque-state",
          "code_challenge" => challenge,
          "code_challenge_method" => "S256"
        })

      %URI{query: query} = conn |> redirected_to() |> URI.parse()

      body =
        build_conn()
        |> post("/api/oauth/token", %{
          "grant_type" => "authorization_code",
          "code" => URI.decode_query(query)["code"],
          "client_id" => client.client_id,
          "redirect_uri" => hd(client.redirect_uris),
          "code_verifier" => verifier
        })
        |> json_response(200)

      assert body["scope"] =~ "docs:#{name}"
      refute Map.has_key?(body, "sso_reauth_required")
    end

    # Approving hands the client's own session a copy of the organization
    # access this browser is carrying, so a stolen cookie is otherwise enough.
    test "asks for the password before a consent hands organization access on", context do
      require_sso(context)
      {conn, browser} = login(context.member, sudo_at: minutes_ago(60))
      authenticate(context, context.member, browser)

      client = insert(:oauth_client, allowed_scopes: ["api:read", "docs"])

      conn =
        get(conn, "/oauth/authorize", %{
          "client_id" => client.client_id,
          "redirect_uri" => hd(client.redirect_uris),
          "response_type" => "code",
          "scope" => "docs:#{context.organization.name}",
          "state" => "state",
          "code_challenge" => "VeRkYllVqy6XLHXPgfpoJxXX_3dxEB2Nb7eJZ5T4aIA",
          "code_challenge_method" => "S256"
        })

      assert redirected_to(conn) =~ "/sudo"
    end

    test "leaves a consent with no organization access to hand on alone", context do
      require_sso(context)
      {conn, _browser} = login(context.member, sudo_at: minutes_ago(60))

      client = insert(:oauth_client, allowed_scopes: ["api:read"])

      conn =
        get(conn, "/oauth/authorize", %{
          "client_id" => client.client_id,
          "redirect_uri" => hd(client.redirect_uris),
          "response_type" => "code",
          "scope" => "api:read",
          "state" => "state",
          "code_challenge" => "VeRkYllVqy6XLHXPgfpoJxXX_3dxEB2Nb7eJZ5T4aIA",
          "code_challenge_method" => "S256"
        })

      assert html_response(conn, 200)
    end

    # Someone signing out because their cookie was stolen means the access it
    # handed out as well.
    test "revoking the browser session takes the copy it handed out with it", context do
      require_sso(context)
      {conn, browser} = login(context.member)
      authenticate(context, context.member, browser)

      name = context.organization.name
      client = insert(:oauth_client, allowed_scopes: ["api:read", "docs"])
      verifier = "code-verifier-#{System.unique_integer([:positive])}"
      challenge = :sha256 |> :crypto.hash(verifier) |> Base.url_encode64(padding: false)

      conn =
        post(conn, "/oauth/authorize", %{
          "client_id" => client.client_id,
          "redirect_uri" => hd(client.redirect_uris),
          "action" => "approve",
          "scope" => "docs:#{name}",
          "selected_scopes" => ["docs:#{name}"],
          "state" => "opaque-state",
          "code_challenge" => challenge,
          "code_challenge_method" => "S256"
        })

      %URI{query: query} = conn |> redirected_to() |> URI.parse()

      body =
        build_conn()
        |> post("/api/oauth/token", %{
          "grant_type" => "authorization_code",
          "code" => URI.decode_query(query)["code"],
          "client_id" => client.client_id,
          "redirect_uri" => hd(client.redirect_uris),
          "code_verifier" => verifier
        })
        |> json_response(200)

      assert body["scope"] =~ "docs:#{name}"

      {:ok, _} = Hexpm.UserSessions.revoke(browser, nil, audit: test_audit_data(context.member))

      refreshed =
        build_conn()
        |> post("/api/oauth/token", %{
          "grant_type" => "refresh_token",
          "refresh_token" => body["refresh_token"],
          "client_id" => client.client_id
        })
        |> json_response(200)

      refute refreshed["scope"] =~ "docs:#{name}"
      assert refreshed["sso_reauth_required"] == [name]
    end

    test "the device approval page names the organizations still to authenticate", context do
      require_sso(context)
      {conn, _browser} = login(context.member)

      client = insert(:oauth_client)

      {:ok, response} =
        Hexpm.OAuth.DeviceCodes.initiate_device_authorization(
          build_conn(),
          client.client_id,
          ["api:read", "repositories"]
        )

      body =
        conn
        |> Plug.Conn.put_session("device_code_verified", %{
          "user_code" => response.user_code,
          "verified_at" => NaiveDateTime.to_iso8601(NaiveDateTime.utc_now())
        })
        |> get("/oauth/device/authorize")
        |> html_response(200)

      assert body =~ "Authenticate to #{context.organization.name}"
      assert body =~ "/sso/org/#{context.organization.name}"
    end

    test "the consent page names the organizations still to authenticate", context do
      require_sso(context)
      {conn, _browser} = login(context.member)

      client = insert(:oauth_client, allowed_scopes: ["api:read", "repositories"])

      body =
        conn
        |> get("/oauth/authorize", %{
          "client_id" => client.client_id,
          "redirect_uri" => hd(client.redirect_uris),
          "response_type" => "code",
          "scope" => "repositories",
          "state" => "state",
          "code_challenge" => "VeRkYllVqy6XLHXPgfpoJxXX_3dxEB2Nb7eJZ5T4aIA",
          "code_challenge_method" => "S256"
        })
        |> html_response(200)

      assert body =~ "Authenticate to #{context.organization.name}"
      assert body =~ "/sso/org/#{context.organization.name}"
    end

    test "a device approved in a browser that has not authenticated says so", context do
      require_sso(context)
      {conn, _browser} = login(context.member)

      client = insert(:oauth_client)

      {:ok, response} =
        Hexpm.OAuth.DeviceCodes.initiate_device_authorization(
          build_conn(),
          client.client_id,
          ["api:read", "repositories"]
        )

      conn
      |> Plug.Conn.put_session("device_code_verified", %{
        "user_code" => response.user_code,
        "verified_at" => NaiveDateTime.to_iso8601(NaiveDateTime.utc_now())
      })
      |> post("/oauth/device/authorize", %{
        "action" => "authorize",
        "selected_scopes" => ["api:read", "repositories"]
      })

      body =
        build_conn()
        |> post("/api/oauth/token", %{
          "grant_type" => "urn:ietf:params:oauth:grant-type:device_code",
          "device_code" => response.device_code,
          "client_id" => client.client_id
        })
        |> json_response(200)

      # Approval is not refused: repositories reaches every organization the
      # member belongs to, so the grant takes what the browser holds and names
      # what it could not.
      refute body["scope"] =~ "repository:#{context.organization.name}"
      assert body["sso_reauth_required"] == [context.organization.name]
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

  describe "package listings" do
    test "leave a governed organization's packages out of the API index", context do
      require_sso(context)
      key = insert(:key, user: context.member, organization: nil)

      body =
        build_conn()
        |> put_req_header("authorization", key.user_secret)
        |> get("/api/packages")
        |> json_response(200)

      refute context.package.name in Enum.map(body, & &1["name"])
    end

    test "leave them out of the caller's own API profile", context do
      insert(:package_owner, package: context.package, user: context.member)
      require_sso(context)
      key = insert(:key, user: context.member, organization: nil)

      body =
        build_conn()
        |> put_req_header("authorization", key.user_secret)
        |> get("/api/users/me")
        |> json_response(200)

      refute context.package.name in Map.keys(body["owned_packages"] || %{})
      refute context.package.name in (body["packages"] || [])
    end

    test "leave them out of a dependant count", context do
      dependency = insert(:package, repository_id: 1)
      insert(:release, package: dependency, version: "1.0.0")

      insert(:release,
        package: context.package,
        version: "2.0.0",
        requirements: [build(:requirement, requirement: "~> 1.0", dependency: dependency)]
      )

      require_sso(context)
      {conn, _session} = login(context.member)

      refute get(conn, "/packages/#{dependency.name}/dependents") |> response(200) =~
               "Dependants (1)"
    end

    test "put them back once the session has authenticated", context do
      require_sso(context)
      session = oauth_session(context.member)
      authenticate(context, context.member, session)
      token = oauth_token(context.member, ["api:read", "repositories"], session)

      body =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token.access_token}")
        |> get("/api/packages")
        |> json_response(200)

      assert context.package.name in Enum.map(body, & &1["name"])
    end

    test "leave them off the owner's profile", context do
      insert(:package_owner, package: context.package, user: context.member)
      {conn, _session} = login(context.member)

      assert package_card_paths(conn, context.member) == [
               "/packages/#{context.repository.name}/#{context.package.name}"
             ]

      require_sso(context)

      assert package_card_paths(conn, context.member) == []
    end

    test "leave them out of search", context do
      {conn, session} = login(context.member)
      path = "/packages?search=#{context.package.name}"

      assert get(conn, path) |> response(200) =~
               "#{context.repository.name}/#{context.package.name}"

      require_sso(context)

      refute get(conn, path) |> response(200) =~
               "#{context.repository.name}/#{context.package.name}"

      authenticate(context, context.member, session)

      assert get(conn, path) |> response(200) =~
               "#{context.repository.name}/#{context.package.name}"
    end
  end

  describe "membership listings" do
    test "leave a governed organization out of the API organization index", context do
      token = oauth_token(context.member, ["api:read"])

      names = fn ->
        build_conn()
        |> put_req_header("authorization", "Bearer #{token.access_token}")
        |> get("/api/orgs")
        |> json_response(200)
        |> Enum.map(& &1["name"])
      end

      assert context.organization.name in names.()

      require_sso(context)

      refute context.organization.name in names.()
    end

    test "leave its repository out of the API repository index", context do
      token = oauth_token(context.member, ["api:read"])

      names = fn ->
        build_conn()
        |> put_req_header("authorization", "Bearer #{token.access_token}")
        |> get("/api/repos")
        |> json_response(200)
        |> Enum.map(& &1["name"])
      end

      assert context.repository.name in names.()

      require_sso(context)

      refute context.repository.name in names.()
      assert "hexpm" in names.()
    end
  end

  describe "a token exchanged from a personal key" do
    test "keeps the organizations that accept personal keys", context do
      require_sso(context, "allow")
      key = insert(:key, user: context.member, organization: nil, permissions: repository_all())

      body = client_credentials(key.user_secret, "repositories")

      assert body["scope"] =~ "repository:#{context.organization.name}"
      refute body["sso_reauth_required"]
    end

    test "loses the ones that do not, and is told nothing to fix", context do
      require_sso(context)
      key = insert(:key, user: context.member, organization: nil, permissions: repository_all())

      body = client_credentials(key.user_secret, "repositories")

      refute body["scope"] =~ "repository:#{context.organization.name}"
      assert body["sso_reauth_required"] in [nil, []]
    end

    test "reaches the organization on the terms the key itself reaches it on", context do
      require_sso(context, "allow")
      key = insert(:key, user: context.member, organization: nil, permissions: api_and_repos())

      body = client_credentials(key.user_secret, "api:read repositories")

      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{body["access_token"]}")
        |> get("/api/orgs/#{context.organization.name}")

      # Its session can never hold organization access, so judging it on one
      # would refuse it where the key it came from is allowed.
      assert json_response(conn, 200)["name"] == context.organization.name
    end

    test "is turned away where the organization turns personal keys away", context do
      require_sso(context)
      key = insert(:key, user: context.member, organization: nil, permissions: api_and_repos())

      body = client_credentials(key.user_secret, "api:read repositories")

      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{body["access_token"]}")
        |> get("/api/orgs/#{context.organization.name}")

      assert json_response(conn, 403)["message"] =~ "does not accept personal API keys"
    end
  end

  describe "a member of two governed organizations" do
    test "resolves them one at a time on the web", context do
      require_sso(context)
      other = second_organization(context)
      {conn, session} = login(context.member)
      authenticate(other, context.member, session)

      assert response(get(conn, "/packages/#{other.repository.name}/#{other.package.name}"), 200) =~
               other.package.name

      unresolved = get(conn, "/packages/#{context.repository.name}/#{context.package.name}")
      assert redirected_to(unresolved) =~ "/sso/org/#{context.organization.name}?return="
    end

    test "keeps the scope it has and names only the one it is missing", context do
      require_sso(context)
      other = second_organization(context)
      session = oauth_session(context.member)
      authenticate(other, context.member, session)

      token = oauth_token(context.member, ["api:read", "repositories"], session)

      assert "repository:#{other.organization.name}" in token.scopes
      refute "repository:#{context.organization.name}" in token.scopes
      assert token.sso_reauth_required == [context.organization.name]
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

  defp second_organization(context) do
    organization = insert(:organization)
    repository = insert(:repository, organization: organization, name: organization.name)
    package = insert(:package, repository_id: repository.id)
    insert(:release, package: package, version: "1.0.0")
    insert(:organization_user, organization: organization, user: context.admin, role: "admin")
    insert(:organization_user, organization: organization, user: context.member, role: "write")

    config = Application.fetch_env!(:hexpm, :organization_sso)

    Application.put_env(
      :hexpm,
      :organization_sso,
      Keyword.put(config, :beta_organizations, [context.organization.name, organization.name])
    )

    connection =
      insert(:organization_sso_connection,
        organization: organization,
        tested_at: DateTime.utc_now(),
        enabled_at: DateTime.utc_now()
      )

    link(connection, organization, context.admin)

    {:ok, connection} =
      SSO.configure_enforcement(
        organization,
        %{"enforcement_mode" => "required", "personal_keys" => "block"},
        audit: audit_data(context.admin)
      )

    %{
      organization: organization,
      repository: repository,
      package: package,
      connection: connection
    }
  end

  defp login(user, opts \\ []) do
    {:ok, session, token} =
      Hexpm.UserSessions.create_browser_session(user,
        name: "Test Browser Session",
        audit: test_audit_data(user)
      )

    sudo_at = Keyword.get(opts, :sudo_at, NaiveDateTime.utc_now())

    conn =
      Plug.Test.init_test_session(build_conn(), %{
        "session_token" => Base.encode64(token),
        "sudo_authenticated_at" => NaiveDateTime.to_iso8601(sudo_at)
      })

    {conn, session}
  end

  defp minutes_ago(minutes) do
    NaiveDateTime.add(NaiveDateTime.utc_now(), -minutes * 60, :second)
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

  defp oauth_session(user) do
    client = insert(:oauth_client)
    insert(:oauth_session, user: user, client_id: client.client_id)
  end

  defp oauth_token(user, scopes, session \\ nil) do
    session = session || oauth_session(user)

    {:ok, token} =
      Hexpm.OAuth.Tokens.create_and_insert_for_user(
        user,
        session.client_id,
        scopes,
        "authorization_code",
        "test_grant_ref-#{System.unique_integer([:positive])}",
        user_session_id: session.id,
        with_refresh_token: true
      )

    token
  end

  defp refresh(token, session) do
    build_conn()
    |> post("/api/oauth/token", %{
      "grant_type" => "refresh_token",
      "refresh_token" => token.refresh_token,
      "client_id" => session.client_id
    })
    |> json_response(200)
  end

  defp api_write, do: [%{domain: "api", resource: "write"}]

  defp repository_all, do: [build(:key_permission, domain: "repositories", resource: nil)]

  defp api_and_repos do
    [
      build(:key_permission, domain: "api", resource: "read"),
      build(:key_permission, domain: "repositories", resource: nil)
    ]
  end

  defp client_credentials(secret, scope) do
    {:ok, client} =
      Hexpm.OAuth.Client.build(%{
        client_id: Hexpm.OAuth.Clients.generate_client_id(),
        name: "Test OAuth Client",
        client_type: "public",
        allowed_grant_types: ["client_credentials"],
        allowed_scopes: ["api", "api:read", "repositories"]
      })
      |> Repo.insert()

    build_conn()
    |> post("/api/oauth/token", %{
      "grant_type" => "client_credentials",
      "client_id" => client.client_id,
      "client_secret" => secret,
      "scope" => scope
    })
    |> json_response(200)
  end

  defp enable_tfa(user) do
    user
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.put_embed(:tfa, %Hexpm.Accounts.TFA{
      secret: Hexpm.Accounts.TFA.generate_secret()
    })
    |> Repo.update!()
  end

  defp otp(user), do: Hexpm.Accounts.TFA.time_based_token(user.tfa.secret)

  defp remove_member(context, user) do
    Repo.delete_all(
      from(member in Hexpm.Accounts.OrganizationUser,
        where: member.organization_id == ^context.organization.id,
        where: member.user_id == ^user.id
      )
    )
  end

  defp expire_org_sessions(session) do
    Repo.update_all(
      from(s in Hexpm.Accounts.SSO.OrgSession, where: s.user_session_id == ^session.id),
      set: [expires_at: DateTime.add(DateTime.utc_now(), -1, :second)]
    )
  end

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

  defp package_card_paths(conn, user) do
    document =
      conn |> get("/users/#{user.username}") |> response(200) |> LazyHTML.from_document()

    document
    |> LazyHTML.query("a[href^='/packages/']")
    |> LazyHTML.attribute("href")
  end

  defp put_ready_cache(request, count) do
    for index <- 0..(count - 1) do
      Cache.put_piece!(request, index, %{type: "too_large", file: "file-#{index}.bin"})
    end

    Cache.put_metadata!(request, %{
      total_diffs: count,
      total_additions: count,
      total_deletions: count,
      files_changed: count,
      files: Enum.map(0..(count - 1), &"file-#{&1}.bin")
    })
  end
end
