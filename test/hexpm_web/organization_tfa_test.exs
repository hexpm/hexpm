defmodule HexpmWeb.OrganizationTFATest do
  use HexpmWeb.ConnCase
  import Phoenix.LiveViewTest
  alias Hexpm.Accounts.{SSO, OrganizationAuth, TFA}
  alias Hexpm.Repository.{Packages, Owners}
  alias Hexpm.OAuth.Tokens

  setup do
    PlugAttack.Storage.Ets.clean(HexpmWeb.Plugs.Attack.Storage)
    app_env(:hexpm, :organization_tfa, mode: :enabled, beta_organizations: [])
    stub(Hexpm.Billing.Mock, :get, fn _, _ -> nil end)
    admin = insert(:user_with_tfa)
    member = insert(:user)
    organization = insert(:organization)
    insert(:organization_user, organization: organization, user: admin, role: "admin")
    insert(:organization_user, organization: organization, user: member, role: "read")
    %{admin: admin, member: member, organization: organization}
  end

  defp enforce(c) do
    c.organization
    |> Ecto.Changeset.change(tfa_required_at: DateTime.add(DateTime.utc_now(), -1))
    |> Repo.update!()
  end

  defp browser(user), do: build_conn() |> test_login(user) |> get("/dashboard/security")

  # Walks the security page's enrollment flow and returns the conn after the
  # verification POST, whose redirect is the stored return path.
  defp enroll(conn) do
    conn = conn |> recycle() |> post("/dashboard/security/enable-tfa")
    secret = get_session(conn, :tfa_setup_secret)

    conn
    |> recycle()
    |> post("/dashboard/security/verify-tfa-code", %{
      "verification_code" => TFA.time_based_token(secret)
    })
  end

  test "only administrators see other members' enrollment on the members page and API", c do
    admin_body =
      browser(c.admin)
      |> recycle()
      |> get("/dashboard/orgs/#{c.organization.name}/members")
      |> html_response(200)

    assert admin_body =~ "2FA enrollment pending"
    assert admin_body =~ "2FA enabled"
    assert admin_body =~ "Require two-factor authentication"
    assert admin_body =~ "value=\"14\""

    body =
      browser(c.member)
      |> recycle()
      |> get("/dashboard/orgs/#{c.organization.name}/members")
      |> html_response(200)

    refute body =~ "2FA enrollment pending"
    refute body =~ "2FA enabled"
    refute body =~ "organization-tfa-policy"

    for {user, visible?} <- [{c.admin, true}, {c.member, false}] do
      body =
        build_conn()
        |> put_req_header("authorization", key_for(user))
        |> get("/api/orgs/#{c.organization.name}/members")
        |> json_response(200)

      assert Enum.all?(body, &(Map.has_key?(&1, "tfa_status") == visible?))
    end

    body =
      build_conn()
      |> put_req_header("authorization", key_for(c.organization))
      |> get("/api/orgs/#{c.organization.name}/members")
      |> json_response(200)

    refute Enum.any?(body, &Map.has_key?(&1, "tfa_status"))
  end

  test "beta controls and policy POSTs are limited to allowed organizations", c do
    conn = browser(c.admin)
    path = "/dashboard/orgs/#{c.organization.name}"

    for rollout <- [
          [mode: :off, beta_organizations: [c.organization.name]],
          [mode: :beta, beta_organizations: []],
          [mode: :beta, beta_organizations: [c.organization.name <> "_other"]]
        ] do
      app_env(:hexpm, :organization_tfa, rollout)
      body = conn |> recycle() |> get(path <> "/members") |> html_response(200)
      refute body =~ "organization-tfa-policy"
      refused = conn |> recycle() |> post(path <> "/tfa", %{policy: %{enforcement: "immediate"}})
      assert redirected_to(refused) == path <> "/members"
      assert Phoenix.Flash.get(refused.assigns.flash, :error) =~ "unavailable"
      refute Repo.get!(Hexpm.Accounts.Organization, c.organization.id).tfa_required_at
    end

    app_env(:hexpm, :organization_tfa, mode: :beta, beta_organizations: [c.organization.name])
    body = conn |> recycle() |> get(path <> "/members") |> html_response(200)
    assert body =~ "organization-tfa-policy"
    accepted = conn |> recycle() |> post(path <> "/tfa", %{policy: %{enforcement: "immediate"}})
    assert redirected_to(accepted) == path <> "/members"
    deadline = Repo.get!(Hexpm.Accounts.Organization, c.organization.id).tfa_required_at
    assert deadline

    app_env(:hexpm, :organization_tfa, mode: :beta, beta_organizations: [])
    body = conn |> recycle() |> get(path <> "/members") |> html_response(200)
    assert body =~ "organization-tfa-policy"
    kept = conn |> recycle() |> post(path <> "/tfa", %{policy: %{enforcement: "keep"}})
    assert Phoenix.Flash.get(kept.assigns.flash, :info) =~ "updated"
    assert Repo.get!(Hexpm.Accounts.Organization, c.organization.id).tfa_required_at == deadline

    app_env(:hexpm, :organization_tfa, mode: :off, beta_organizations: [])
    body = conn |> recycle() |> get(path <> "/members") |> html_response(200)
    assert body =~ "organization-tfa-policy"
    disabled = conn |> recycle() |> post(path <> "/tfa", %{policy: %{enforcement: "disabled"}})
    assert Phoenix.Flash.get(disabled.assigns.flash, :info) =~ "updated"
    body = conn |> recycle() |> get(path <> "/members") |> html_response(200)
    refute body =~ "organization-tfa-policy"
    refused = conn |> recycle() |> post(path <> "/tfa", %{policy: %{enforcement: "immediate"}})
    assert Phoenix.Flash.get(refused.assigns.flash, :error) =~ "unavailable"
  end

  test "policy selects preserve the available actions", c do
    conn = browser(c.admin)
    now = DateTime.utc_now()

    for {deadline, actions, selected} <- [
          {nil, ["transition", "immediate", "disabled"], "transition"},
          {DateTime.add(now, 86400), ["keep", "transition", "immediate", "disabled"], "keep"},
          {DateTime.add(now, -1), ["keep", "disabled"], "keep"}
        ] do
      c.organization |> Ecto.Changeset.change(tfa_required_at: deadline) |> Repo.update!()

      document =
        conn
        |> recycle()
        |> get("/dashboard/orgs/#{c.organization.name}/members")
        |> html_response(200)
        |> LazyHTML.from_document()

      assert document
             |> LazyHTML.query("#policy-enforcement option")
             |> LazyHTML.attribute("value") ==
               actions

      assert document
             |> LazyHTML.query("#policy-enforcement option[selected]")
             |> LazyHTML.attribute("value") == [selected]

      assert LazyHTML.query(document, "#policy-tfa-session-lifetime") |> Enum.empty?()
    end
  end

  test "an unenrolled member is sent to enrollment and returns after enabling 2FA", c do
    enforce(c)

    assert browser(c.admin)
           |> recycle()
           |> get("/dashboard/orgs/#{c.organization.name}/members")
           |> html_response(200)

    conn = browser(c.member)
    response = conn |> recycle() |> get("/dashboard/orgs/#{c.organization.name}/members")
    assert redirected_to(response) =~ "/organizations/#{c.organization.name}/authenticate"
    response = response |> recycle() |> get(redirected_to(response))
    assert redirected_to(response) == "/dashboard/security"

    assert Phoenix.Flash.get(response.assigns.flash, :error) ==
             "Organization #{c.organization.name} requires two-factor authentication. Enable it in your account security settings."

    assert get_session(response, :tfa_return_to) =~
             "/organizations/#{c.organization.name}/authenticate"

    response = enroll(response)
    assert redirected_to(response) =~ "/organizations/#{c.organization.name}/authenticate"
    refute get_session(response, :tfa_return_to)
    response = response |> recycle() |> get(redirected_to(response))
    assert redirected_to(response) == "/dashboard/orgs/#{c.organization.name}/members"
    assert response |> recycle() |> get(redirected_to(response)) |> html_response(200)
  end

  test "the deadline is shown as a readable UTC date on the page and in email", c do
    c.organization
    |> Ecto.Changeset.change(tfa_required_at: ~U[2026-09-29 01:04:53.493658Z])
    |> Repo.update!()

    body =
      browser(c.admin)
      |> recycle()
      |> get("/dashboard/orgs/#{c.organization.name}/members")
      |> html_response(200)

    assert body =~ "Enforcement deadline: <strong>September 29, 2026 at 01:04 UTC</strong>"
    refute body =~ "2026-09-29T01:04:53"

    organization = Repo.get!(Hexpm.Accounts.Organization, c.organization.id)
    email = Hexpm.Emails.organization_tfa(organization, "scheduled", ["member@example.com"], [])
    assert email.html_body =~ "from <strong>September 29, 2026 at 01:04 UTC</strong>"
    assert email.text_body =~ "from September 29, 2026 at 01:04 UTC."
  end

  test "an administrator without 2FA can't configure a policy", c do
    unenrolled = insert(:user)
    insert(:organization_user, organization: c.organization, user: unenrolled, role: "admin")
    params = %{policy: %{enforcement: "transition", grace_days: "14"}}
    path = "/dashboard/orgs/#{c.organization.name}/tfa"
    refused = browser(unenrolled) |> recycle() |> post(path, params)
    assert redirected_to(refused) == "/dashboard/security"
    assert Phoenix.Flash.get(refused.assigns.flash, :error) =~ "Enable 2FA"

    assert get_session(refused, :tfa_return_to) ==
             "/dashboard/orgs/#{c.organization.name}/members"

    refute Repo.get!(Hexpm.Accounts.Organization, c.organization.id).tfa_required_at
    accepted = browser(c.admin) |> recycle() |> post(path, params)
    assert redirected_to(accepted) == "/dashboard/orgs/#{c.organization.name}/members"
    assert Repo.get!(Hexpm.Accounts.Organization, c.organization.id).tfa_required_at
  end

  test "the policy deadline comes only from the enforcement choice", c do
    conn = browser(c.admin)
    path = "/dashboard/orgs/#{c.organization.name}/tfa"
    deadline = DateTime.utc_now() |> DateTime.add(3 * 86_400) |> DateTime.to_iso8601()

    conn |> recycle() |> post(path, %{policy: %{tfa_required_at: deadline}})
    refute Repo.get!(Hexpm.Accounts.Organization, c.organization.id).tfa_required_at

    invalid =
      conn
      |> recycle()
      |> post(path, %{policy: %{enforcement: "transition", grace_days: ["14"]}})

    assert Phoenix.Flash.get(invalid.assigns.flash, :error) =~ "Invalid deadline"
    refute Repo.get!(Hexpm.Accounts.Organization, c.organization.id).tfa_required_at

    assert_error_sent 400, fn -> conn |> recycle() |> post(path, %{policy: "immediate"}) end
  end

  test "personal keys of unenrolled members are refused and enrolled members' keys work", c do
    enforce(c)

    response =
      build_conn()
      |> put_req_header("authorization", key_for(c.member))
      |> get("/api/orgs/#{c.organization.name}/members")

    assert response.status in [401, 403]
    assert response.resp_body =~ "two-factor authentication"

    assert build_conn()
           |> put_req_header("authorization", key_for(c.admin))
           |> get("/api/orgs/#{c.organization.name}/members")
           |> json_response(200)
  end

  test "the shared authorization endpoint completes a 2FA-only request after enrollment without extending the target session",
       c do
    enforce(c)
    client = insert(:oauth_client)
    target = insert(:oauth_session, user: c.member, client_id: client.client_id)

    {:ok, token} =
      Tokens.create_and_insert_for_user(
        c.member,
        client.client_id,
        ["api:read", "repository:#{c.organization.name}"],
        "authorization_code",
        nil,
        user_session_id: target.id,
        with_refresh_token: true
      )

    assert token.organization_reauth_required == [
             %{organization: c.organization.name, requirements: ["tfa"]}
           ]

    response =
      build_conn()
      |> put_req_header("authorization", "Bearer #{token.access_token}")
      |> post("/api/oauth/organization_authorization", %{organizations: [c.organization.name]})
      |> json_response(201)

    %URI{path: path, query: query} = URI.parse(response["verification_uri"])
    code = URI.decode_query(query)["code"]
    conn = browser(c.member)
    conn = conn |> recycle() |> get(path <> "?" <> query)
    assert html_response(conn, 200) =~ "2FA enrollment required"
    conn = conn |> recycle() |> post(path, %{code: code, organization: c.organization.name})
    assert redirected_to(conn) == "/dashboard/security"

    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~
             "requires two-factor authentication"

    conn = enroll(conn)
    assert redirected_to(conn) == path <> "?" <> query
    conn = conn |> recycle() |> get(redirected_to(conn))
    assert redirected_to(conn) == "/dashboard"
    assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "authenticated"
    assert Repo.get!(Hexpm.UserSession, target.id).expires_at == target.expires_at
    assert SSO.get_authorization(code, c.member) == nil

    {:ok, refreshed} =
      Tokens.revoke_and_create_token(
        Repo.preload(token, :user),
        client.client_id,
        token.granted_scopes,
        "refresh_token",
        nil,
        user_session_id: target.id,
        with_refresh_token: true
      )

    assert "repository:#{c.organization.name}" in refreshed.scopes
    assert refreshed.organization_reauth_required == []
  end

  test "account mismatch, expiry, and revocation grant no access", c do
    enforce(c)
    client = insert(:oauth_client)

    for failure <- [:mismatch, :expired, :revoked] do
      target = insert(:oauth_session, user: c.member, client_id: client.client_id)
      {:ok, authorization} = SSO.request_authorization(c.member, target.id, [c.organization.name])
      code = authorization.raw_code
      user = if failure == :mismatch, do: c.admin, else: c.member
      conn = browser(user)

      case failure do
        :expired ->
          authorization
          |> Ecto.Changeset.change(expires_at: DateTime.add(DateTime.utc_now(), -1))
          |> Repo.update!()

        :revoked ->
          target |> Ecto.Changeset.change(revoked_at: DateTime.utc_now()) |> Repo.update!()

        :mismatch ->
          :ok
      end

      conn = conn |> recycle() |> get("/organizations/authorize", %{code: code})
      assert redirected_to(conn) == "/dashboard"
      refute Phoenix.Flash.get(conn.assigns.flash, :info)
      assert OrganizationAuth.check(c.organization, c.member) == {:error, :tfa_required}
    end
  end

  test "LiveView search and report events recheck enrollment", c do
    enforce(c)
    repository = insert(:repository, organization: c.organization, name: c.organization.name)
    package = insert(:package, repository_id: repository.id)
    insert(:release, package: package, version: "1.0.0")
    conn = browser(c.admin)
    {:ok, search, html} = live(recycle(conn), "/packages?search=#{package.name}")
    assert html =~ "#{repository.name}/#{package.name}"

    {:ok, report, _html} =
      live(recycle(conn), "/packages/#{repository.name}/#{package.name}/report")

    Repo.update!(Hexpm.Accounts.User.clear_tfa(c.admin))

    refute render_patch(search, "/packages?search=#{package.name}&sort=name") =~
             "#{repository.name}/#{package.name}"

    assert {:error, {:redirect, %{to: to}}} =
             render_submit(report, "submit", %{
               "h-captcha-response" => "captcha",
               "report" => %{
                 reason: "other",
                 summary: "Question",
                 description: "Report details"
               }
             })

    assert to =~ "/organizations/#{c.organization.name}/authenticate"
    refute Repo.exists?(Hexpm.PackageReports.Report)
  end

  test "edge authorization rejects unenrolled members' keys for private resources and public ownership",
       c do
    repository = insert(:repository, organization: c.organization, name: c.organization.name)
    private = insert(:package, repository_id: repository.id)
    public = insert(:package, repository_id: 1)
    organization = Repo.preload(c.organization, :user)
    insert(:package_owner, package: public, user: organization.user, level: "full")
    unenrolled = insert(:user)
    insert(:organization_user, organization: c.organization, user: unenrolled, role: "admin")

    permissions = [
      %{"domain" => "api"},
      %{"domain" => "repositories"},
      %{"domain" => "docs", "resource" => repository.name}
    ]

    secret = key_for(unenrolled, permissions)
    enrolled = key_for(c.admin, permissions)
    enforce(c)

    for {domain, resource} <- [
          {"repository", repository.name},
          {"docs", repository.name}
        ] do
      response =
        build_conn()
        |> put_req_header("authorization", secret)
        |> get("/api/auth", domain: domain, resource: resource)

      assert response.status == 403, "#{domain}: #{response.resp_body}"
      assert response.resp_body =~ "two-factor authentication"

      assert build_conn()
             |> put_req_header("authorization", enrolled)
             |> get("/api/auth", domain: domain, resource: resource)
             |> json_response(200)
    end

    {:ok, token} =
      Tokens.create_and_insert_for_user(
        unenrolled,
        insert(:oauth_client).client_id,
        ["api"],
        "authorization_code"
      )

    for resource <- ["#{repository.name}/#{private.name}", "hexpm/#{public.name}"] do
      response =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token.access_token}")
        |> get("/api/auth", domain: "package", resource: resource)

      assert json_response(response, 403)["message"] =~ "two-factor authentication"
    end

    response =
      build_conn()
      |> put_req_header("authorization", secret)
      |> put("/api/packages/#{public.name}/owners/#{hd(c.member.emails).email}")

    assert json_response(response, 403)["message"] =~ "two-factor authentication"

    own_key = key_for(organization, [%{"domain" => "repository", "resource" => repository.name}])

    response =
      build_conn()
      |> put_req_header("authorization", own_key)
      |> get("/api/auth", domain: "repository", resource: repository.name)

    assert json_response(response, 200)["key"]["owner"]["type"] == "organization"
  end

  test "organization enforcement preserves independent full public-package ownership" do
    stub(Hexpm.Billing.Mock, :get, fn _, _ -> nil end)
    user = insert(:user)
    organization = insert(:organization) |> Repo.preload(:user)
    insert(:repository, organization: organization, name: organization.name)

    insert(:organization_user,
      user: insert(:user_with_tfa),
      organization: organization,
      role: "admin"
    )

    insert(:organization_user, user: user, organization: organization, role: "admin")
    package = insert(:package, repository_id: 1) |> Repo.preload(repository: :organization)
    insert(:package_owner, package: package, user: organization.user, level: "full")
    assert {:ok, _} = Owners.add(package, user, %{"level" => "full"}, audit: audit_data(user))
    assert Packages.owner_with_access?(package, user, "full")
    conn = build_conn() |> test_login(user)
    assert conn |> get("/packages/#{package.name}/owners") |> html_response(200)

    Repo.update!(
      Ecto.Changeset.change(organization, tfa_required_at: DateTime.add(DateTime.utc_now(), -1))
    )

    refused = conn |> get("/packages/#{package.name}/owners")
    assert html_response(refused, 200)
    owner = Owners.get(package, user)
    Repo.update!(Ecto.Changeset.change(owner, level: "maintainer"))
    limited = conn |> get("/packages/#{package.name}/owners")
    assert redirected_to(limited) =~ "/organizations/#{organization.name}/authenticate"

    Repo.update!(
      Ecto.Changeset.change(Repo.get!(Hexpm.Repository.PackageOwner, owner.id), level: "full")
    )

    # Direct package ownership still suffices after the organization membership is removed.
    assert :ok =
             Hexpm.Accounts.Organizations.remove_member(organization, user,
               audit: audit_data(user)
             )

    assert conn |> get("/packages/#{package.name}/owners") |> html_response(200)
  end

  test "shared authorization resumes after sudo and completes for an enrolled member" do
    user = insert(:user_with_tfa)
    organization = insert(:organization, tfa_required_at: DateTime.add(DateTime.utc_now(), -1))
    insert(:organization_user, user: user, organization: organization, role: "admin")
    target = insert(:oauth_session, user: user, client_id: insert(:oauth_client).client_id)
    {:ok, request} = SSO.request_authorization(user, target.id, [organization.name])

    conn =
      build_conn()
      |> test_login(user, sudo: false)
      |> get("/organizations/authorize", %{code: request.raw_code})

    assert redirected_to(conn) == "/sudo"

    conn =
      conn
      |> recycle()
      |> post("/sudo", %{type: "tfa", code: TFA.time_based_token(user.tfa.secret)})

    assert redirected_to(conn) =~ "/organizations/authorize"
    assert HexpmWeb.Plugs.Sudo.sudo_active?(conn)
    conn = conn |> recycle() |> get(redirected_to(conn))
    assert redirected_to(conn) == "/dashboard"
    assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "authenticated"
    refute SSO.get_authorization(request.raw_code, user)
    assert Repo.get!(Hexpm.UserSession, target.id).expires_at == target.expires_at
  end
end
