defmodule HexpmWeb.OrganizationTFATest do
  use HexpmWeb.ConnCase
  import Phoenix.LiveViewTest
  alias Hexpm.Accounts.{TFASessions, SSO, OrganizationAuth}
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
    {:ok, :ok} = TFASessions.record_verified!(c.admin, conn.assigns.current_session.id)
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
    assert Repo.get!(Hexpm.Accounts.Organization, c.organization.id).tfa_required_at

    app_env(:hexpm, :organization_tfa, mode: :beta, beta_organizations: [])
    body = conn |> recycle() |> get(path <> "/members") |> html_response(200)
    assert body =~ "organization-tfa-policy"

    changed =
      conn
      |> recycle()
      |> post(path <> "/tfa", %{policy: %{tfa_session_lifetime_seconds: "86400"}})

    assert Phoenix.Flash.get(changed.assigns.flash, :info) =~ "updated"

    assert Repo.get!(Hexpm.Accounts.Organization, c.organization.id).tfa_session_lifetime_seconds ==
             86400

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

  test "policy selects preserve the available actions and selected verification interval", c do
    conn = browser(c.admin)
    {:ok, :ok} = TFASessions.record_verified!(c.admin, conn.assigns.current_session.id)
    now = DateTime.utc_now()

    for {deadline, interval, actions, selected} <- [
          {nil, 604_800, ["transition", "immediate", "disabled"], "transition"},
          {DateTime.add(now, 86400), 86400, ["keep", "transition", "immediate", "disabled"],
           "keep"},
          {DateTime.add(now, -1), 2_592_000, ["keep", "disabled"], "keep"}
        ] do
      c.organization
      |> Ecto.Changeset.change(
        tfa_required_at: deadline,
        tfa_session_lifetime_seconds: interval
      )
      |> Repo.update!()

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

      assert document
             |> LazyHTML.query("#policy-tfa-session-lifetime option")
             |> LazyHTML.attribute("value") == ["86400", "604800", "2592000"]

      assert document
             |> LazyHTML.query("#policy-tfa-session-lifetime option[selected]")
             |> LazyHTML.attribute("value") == [to_string(interval)]
    end
  end

  test "an enrolled member needs browser proof; TOTP verification restores organization access",
       c do
    enforce(c)
    conn = browser(c.admin)
    session_id = conn.assigns.current_session.id
    assert TFASessions.proof(c.admin, session_id) == nil
    response = conn |> recycle() |> get("/dashboard/orgs/#{c.organization.name}/members")
    assert redirected_to(response) =~ "/organizations/#{c.organization.name}/authenticate"
    response = response |> recycle() |> get(redirected_to(response))
    assert redirected_to(response) == "/tfa/verify"
    response = response |> recycle() |> get("/tfa/verify")
    assert html_response(response, 200) =~ "2FA verification required"

    response =
      response
      |> recycle()
      |> post("/tfa/verify", %{code: Hexpm.Accounts.TFA.time_based_token(c.admin.tfa.secret)})

    assert TFASessions.proof(c.admin, session_id)
    assert redirected_to(response) =~ "/organizations/#{c.organization.name}/authenticate"
    response = response |> recycle() |> get(redirected_to(response))
    assert redirected_to(response) == "/dashboard/orgs/#{c.organization.name}/members"
  end

  test "recovery codes establish proof without changing credentials", c do
    enforce(c)
    conn = browser(c.admin)
    conn = conn |> recycle() |> post("/tfa/verify", %{code: "1234-1234-1234-1234"})
    assert redirected_to(conn) == "/dashboard/security"
    assert TFASessions.proof(c.admin, conn.assigns.current_session.id)
    assert Repo.get!(Hexpm.Accounts.User, c.admin.id).tfa_generation == c.admin.tfa_generation
    conn = conn |> recycle() |> post("/tfa/verify", %{code: "1234-1234-1234-1234"})
    assert html_response(conn, 200) =~ "2FA verification failed"
  end

  test "verification counts attempts against the sudo code limit", c do
    conn = build_conn() |> test_login(c.admin, sudo: false) |> get("/dashboard/security")

    for _ <- 1..5 do
      conn |> recycle() |> post("/sudo", %{"type" => "tfa", "code" => "000000"})
    end

    blocked =
      conn
      |> recycle()
      |> post("/tfa/verify", %{code: Hexpm.Accounts.TFA.time_based_token(c.admin.tfa.secret)})

    assert html_response(blocked, 200) =~ "2FA verification failed"
    refute get_session(blocked, "sudo_authenticated_at")
    refute TFASessions.proof(c.admin, blocked.assigns.current_session.id)
  end

  test "verification ignores a return path from the query string", c do
    conn = browser(c.admin) |> recycle() |> get("/tfa/verify?return=/dashboard/keys")
    assert html_response(conn, 200) =~ "2FA verification required"
    refute get_session(conn, :tfa_return_to)
  end

  test "fresh proof is required to configure a policy even when the account has 2FA", c do
    conn = browser(c.admin)
    params = %{policy: %{enforcement: "transition", grace_days: "14"}}
    refused = conn |> recycle() |> post("/dashboard/orgs/#{c.organization.name}/tfa", params)
    assert redirected_to(refused) == "/tfa/verify"
    refute Repo.get!(Hexpm.Accounts.Organization, c.organization.id).tfa_required_at
    {:ok, :ok} = TFASessions.record_verified!(c.admin, conn.assigns.current_session.id)
    accepted = conn |> recycle() |> post("/dashboard/orgs/#{c.organization.name}/tfa", params)
    assert redirected_to(accepted) == "/dashboard/orgs/#{c.organization.name}/members"
    assert Repo.get!(Hexpm.Accounts.Organization, c.organization.id).tfa_required_at
  end

  test "the policy deadline comes only from the enforcement choice", c do
    conn = browser(c.admin)
    {:ok, :ok} = TFASessions.record_verified!(c.admin, conn.assigns.current_session.id)
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

  test "general API permissions and exchanged personal keys cannot bypass enforced 2FA", c do
    enforce(c)
    key = key_for(c.admin)

    response =
      build_conn()
      |> put_req_header("authorization", key)
      |> get("/api/orgs/#{c.organization.name}/members")

    assert response.status in [401, 403]
    assert response.resp_body =~ "2FA"
  end

  test "the shared reauthorization endpoint completes a 2FA-only request without extending the target session",
       c do
    enforce(c)
    client = insert(:oauth_client)
    target = insert(:oauth_session, user: c.admin, client_id: client.client_id)

    {:ok, token} =
      Tokens.create_and_insert_for_user(
        c.admin,
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
    conn = browser(c.admin)
    conn = conn |> recycle() |> get(path <> "?" <> query)
    assert html_response(conn, 200) =~ "2FA verification required"
    conn = conn |> recycle() |> post(path, %{code: code, organization: c.organization.name})
    assert redirected_to(conn) == "/tfa/verify"

    conn =
      conn
      |> recycle()
      |> post("/tfa/verify", %{code: Hexpm.Accounts.TFA.time_based_token(c.admin.tfa.secret)})

    assert redirected_to(conn) == path <> "?" <> query
    refute TFASessions.proof(c.admin, target.id)
    conn = conn |> recycle() |> get(redirected_to(conn))
    assert redirected_to(conn) == "/dashboard"
    assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "authenticated"
    assert TFASessions.proof(c.admin, target.id)
    assert Repo.get!(Hexpm.UserSession, target.id).expires_at == target.expires_at

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
  end

  test "documentation verification returns to the registered callback and preserves the session",
       c do
    enforce(c)
    callback = "https://docs.example/oauth/callback?client=docs"
    client = insert(:oauth_client, redirect_uris: [callback])
    target = insert(:oauth_session, user: c.admin, client_id: client.client_id)

    {:ok, token} =
      Tokens.create_and_insert_for_user(
        c.admin,
        client.client_id,
        ["docs:#{c.organization.name}"],
        "authorization_code",
        nil,
        user_session_id: target.id,
        with_refresh_token: true
      )

    response =
      build_conn()
      |> put_req_header("authorization", "Bearer #{token.access_token}")
      |> post("/api/oauth/organization_authorization", %{
        organizations: [c.organization.name],
        redirect_uri: callback,
        state: "docs-state+&="
      })
      |> json_response(201)

    %URI{path: path, query: query} = URI.parse(response["verification_uri"])
    code = URI.decode_query(query)["code"]
    authorization = SSO.get_authorization(code, c.admin)
    assert authorization.redirect_uri == callback
    assert authorization.state == "docs-state+&="

    conn = browser(c.admin) |> recycle() |> get(path <> "?" <> query)
    assert html_response(conn, 200) =~ "2FA verification required"
    conn = conn |> recycle() |> post(path, %{code: code, organization: c.organization.name})
    assert redirected_to(conn) == "/tfa/verify"

    conn =
      conn
      |> recycle()
      |> post("/tfa/verify", %{
        code: Hexpm.Accounts.TFA.time_based_token(c.admin.tfa.secret)
      })

    conn = conn |> recycle() |> get(redirected_to(conn))

    %URI{host: "docs.example", path: "/oauth/callback", query: returned_query} =
      URI.parse(redirected_to(conn))

    assert URI.decode_query(returned_query) == %{
             "client" => "docs",
             "organization_authorization" => "complete",
             "state" => "docs-state+&="
           }

    refute Phoenix.Flash.get(conn.assigns.flash, :info)
    assert TFASessions.proof(c.admin, target.id)
    assert Repo.get!(Hexpm.UserSession, target.id).expires_at == target.expires_at
    assert SSO.get_authorization(code, c.admin) == nil

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

    assert "docs:#{c.organization.name}" in refreshed.scopes
    assert refreshed.organization_reauth_required == []

    conn = conn |> recycle() |> get(path, %{code: code, redirect_uri: "https://evil.example"})
    assert redirected_to(conn) == "/dashboard"
  end

  test "documentation cancellation returns a cancellation result without copying browser proof",
       c do
    enforce(c)
    callback = "https://docs.example/oauth/callback"
    client = insert(:oauth_client, redirect_uris: [callback])
    target = insert(:oauth_session, user: c.admin, client_id: client.client_id)

    {:ok, authorization} =
      SSO.request_authorization(c.admin, target.id, [c.organization.name],
        redirect_uri: callback,
        state: "cancel-state"
      )

    conn = browser(c.admin)
    {:ok, :ok} = TFASessions.record_verified!(c.admin, conn.assigns.current_session.id)

    conn =
      conn
      |> recycle()
      |> post("/organizations/authorize", %{
        code: authorization.raw_code,
        action: "cancel",
        redirect_uri: "https://evil.example",
        state: "forged"
      })

    %URI{host: "docs.example", path: "/oauth/callback", query: query} =
      URI.parse(redirected_to(conn))

    assert URI.decode_query(query) == %{
             "organization_authorization" => "cancelled",
             "state" => "cancel-state"
           }

    refute TFASessions.proof(c.admin, target.id)
    assert SSO.get_authorization(authorization.raw_code, c.admin) == nil

    conn =
      conn
      |> recycle()
      |> post("/organizations/authorize", %{code: authorization.raw_code, action: "cancel"})

    assert redirected_to(conn) == "/dashboard"
  end

  test "invalid browser-return requests never redirect or grant proof", c do
    enforce(c)
    callback = "https://docs.example/oauth/callback"
    client = insert(:oauth_client, redirect_uris: [callback])

    for failure <- [:mismatch, :expired, :revoked] do
      target = insert(:oauth_session, user: c.admin, client_id: client.client_id)

      {:ok, authorization} =
        SSO.request_authorization(c.admin, target.id, [c.organization.name],
          redirect_uri: callback,
          state: "test-state"
        )

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

      user = if failure == :mismatch, do: c.member, else: c.admin

      conn =
        browser(user)
        |> recycle()
        |> get("/organizations/authorize", %{code: authorization.raw_code})

      assert redirected_to(conn) == "/dashboard"
      refute TFASessions.proof(c.admin, target.id)

      conn =
        conn
        |> recycle()
        |> post("/organizations/authorize", %{code: authorization.raw_code, action: "cancel"})

      assert redirected_to(conn) == "/dashboard"
    end
  end

  test "browser-return requests only accept a registered callback of the target client", c do
    enforce(c)
    callback = "https://*.hexdocs.pm/oauth/callback"
    client = insert(:oauth_client, redirect_uris: [callback, "https://localhost/other"])
    other = insert(:oauth_client, redirect_uris: ["https://other.example/oauth/callback"])
    target = insert(:oauth_session, user: c.admin, client_id: client.client_id)

    {:ok, token} =
      Tokens.create_and_insert_for_user(
        c.admin,
        client.client_id,
        ["docs:#{c.organization.name}"],
        "authorization_code",
        nil,
        user_session_id: target.id
      )

    base = %{organizations: [c.organization.name]}

    invalid =
      [
        %{redirect_uri: "https://acme.hexdocs.pm/oauth/callback"},
        %{state: "state"},
        %{redirect_uri: "https://acme.hexdocs.pm/oauth/callback", state: ""},
        %{redirect_uri: "https://acme.hexdocs.pm/oauth/callback", state: <<0>>},
        %{
          redirect_uri: "https://acme.hexdocs.pm/oauth/callback",
          state: String.duplicate("x", 513)
        },
        %{redirect_uri: "https://acme.hexdocs.pm/oauth/callback", state: ["state"]},
        %{redirect_uri: ["https://acme.hexdocs.pm/oauth/callback"], state: "state"}
      ] ++
        Enum.map(
          [
            "https://evil.example/oauth/callback",
            "https://other.example/oauth/callback",
            "https://evil/path.hexdocs.pm/oauth/callback",
            "https://acme%2eevil.hexdocs.pm/oauth/callback",
            "https://localhost/arbitrary.hexdocs.pm/oauth/callback",
            "https://acme.hexdocs.pm:bad/oauth/callback",
            "https://evil?x.hexdocs.pm/oauth/callback",
            "https://evil@acme.hexdocs.pm/oauth/callback",
            "https://acme.hexdocs.pm/oauth/callback#x",
            "https://acme.hexdocs.pm/oauth/callback?state=forged",
            "http://acme.hexdocs.pm/oauth/callback",
            "https://acme.hexdocs.pm.evil.example/oauth/callback",
            "//acme.hexdocs.pm/oauth/callback"
          ],
          &%{redirect_uri: &1, state: "state"}
        )

    for params <- invalid do
      response =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token.access_token}")
        |> post(
          "/api/oauth/organization_authorization",
          Map.merge(base, Map.put(params, :client_id, other.client_id))
        )
        |> json_response(422)

      assert response["message"] =~ "registered callback"
    end

    refute Repo.exists?(SSO.Authorization)

    response =
      build_conn()
      |> put_req_header("authorization", "Bearer #{token.access_token}")
      |> post(
        "/api/oauth/organization_authorization",
        Map.merge(base, %{redirect_uri: "https://acme.hexdocs.pm/oauth/callback", state: "state"})
      )
      |> json_response(201)

    assert response["verification_uri"] =~ "/organizations/authorize?code="

    {:ok, opaque} =
      SSO.request_authorization(c.admin, target.id, [c.organization.name],
        redirect_uri: "https://acme.hexdocs.pm/oauth/callback",
        state: " "
      )

    assert Repo.get!(SSO.Authorization, opaque.id).state == " "
  end

  test "cancellation, account mismatch, expiry, and revocation grant no proof", c do
    enforce(c)
    client = insert(:oauth_client)

    for failure <- [:cancel, :mismatch, :expired, :revoked] do
      target = insert(:oauth_session, user: c.admin, client_id: client.client_id)
      {:ok, authorization} = SSO.request_authorization(c.admin, target.id, [c.organization.name])
      code = authorization.raw_code
      user = if failure == :mismatch, do: c.member, else: c.admin
      conn = browser(user)

      case failure do
        :cancel ->
          conn |> recycle() |> post("/organizations/authorize", %{code: code, action: "cancel"})

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
      refute TFASessions.proof(c.admin, target.id)
    end
  end

  test "cancelling after 2FA verification leaves the target unverified", c do
    enforce(c)
    target = insert(:oauth_session, user: c.admin, client_id: insert(:oauth_client).client_id)
    {:ok, authorization} = SSO.request_authorization(c.admin, target.id, [c.organization.name])
    code = authorization.raw_code
    conn = browser(c.admin)

    conn =
      conn
      |> recycle()
      |> post("/organizations/authorize", %{code: code, organization: c.organization.name})

    conn =
      conn
      |> recycle()
      |> post("/tfa/verify", %{code: Hexpm.Accounts.TFA.time_based_token(c.admin.tfa.secret)})

    assert TFASessions.proof(c.admin, conn.assigns.current_session.id)
    refute TFASessions.proof(c.admin, target.id)
    conn = conn |> recycle() |> post("/organizations/authorize", %{code: code, action: "cancel"})
    conn = conn |> recycle() |> get("/organizations/authorize", %{code: code})
    assert redirected_to(conn) == "/dashboard"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "no longer open"
    refute TFASessions.proof(c.admin, target.id)
  end

  test "opening a verification URL doesn't approve copying fresh browser proof", c do
    enforce(c)
    target = insert(:oauth_session, user: c.admin, client_id: insert(:oauth_client).client_id)
    {:ok, authorization} = SSO.request_authorization(c.admin, target.id, [c.organization.name])
    conn = browser(c.admin)
    {:ok, :ok} = TFASessions.record_verified!(c.admin, conn.assigns.current_session.id)
    conn = conn |> recycle() |> get("/organizations/authorize", %{code: authorization.raw_code})
    assert html_response(conn, 200) =~ "Authenticate"
    refute TFASessions.proof(c.admin, target.id)
  end

  test "LiveView search and report events recheck 2FA expiry", c do
    enforce(c)
    repository = insert(:repository, organization: c.organization, name: c.organization.name)
    package = insert(:package, repository_id: repository.id)
    insert(:release, package: package, version: "1.0.0")
    conn = browser(c.admin)
    session = conn.assigns.current_session
    {:ok, :ok} = TFASessions.record_verified!(c.admin, session.id)
    {:ok, search, html} = live(recycle(conn), "/packages?search=#{package.name}")
    assert html =~ "#{repository.name}/#{package.name}"

    {:ok, report, _html} =
      live(recycle(conn), "/packages/#{repository.name}/#{package.name}/report")

    Repo.update_all(from(s in Hexpm.UserSession, where: s.id == ^session.id),
      set: [tfa_verified_at: DateTime.add(DateTime.utc_now(), -604_800)]
    )

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

  test "edge authorization rejects human keys for private resources and public ownership", c do
    repository = insert(:repository, organization: c.organization, name: c.organization.name)
    private = insert(:package, repository_id: repository.id)
    public = insert(:package, repository_id: 1)
    organization = Repo.preload(c.organization, :user)
    insert(:package_owner, package: public, user: organization.user, level: "full")

    secret =
      key_for(c.admin, [
        %{"domain" => "api"},
        %{"domain" => "repositories"},
        %{"domain" => "docs", "resource" => repository.name}
      ])

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
      assert response.resp_body =~ "2FA"
    end

    {:ok, token} =
      Tokens.create_and_insert_for_user(
        c.admin,
        insert(:oauth_client).client_id,
        ["api"],
        "authorization_code"
      )

    for resource <- ["#{repository.name}/#{private.name}", "hexpm/#{public.name}"] do
      response =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token.access_token}")
        |> get("/api/auth", domain: "package", resource: resource)

      assert json_response(response, 403)["message"] =~ "2FA"
    end

    response =
      build_conn()
      |> put_req_header("authorization", secret)
      |> put("/api/packages/#{public.name}/owners/#{hd(c.member.emails).email}")

    assert json_response(response, 403)["message"] =~ "2FA"

    own_key = key_for(organization, [%{"domain" => "repository", "resource" => repository.name}])

    response =
      build_conn()
      |> put_req_header("authorization", own_key)
      |> get("/api/auth", domain: "repository", resource: repository.name)

    assert json_response(response, 200)["key"]["owner"]["type"] == "organization"
  end

  test "valid older browser proof replaces proof from a revoked source" do
    user = insert(:user_with_tfa)
    organization = insert(:organization, tfa_required_at: DateTime.add(DateTime.utc_now(), -1))
    insert(:organization_user, user: user, organization: organization, role: "admin")
    browser = build_conn() |> test_login(user) |> get("/dashboard/security")
    browser_id = browser.assigns.current_session.id
    {:ok, :ok} = TFASessions.record_verified!(user, browser_id)

    Repo.update_all(from(s in Hexpm.UserSession, where: s.id == ^browser_id),
      set: [tfa_verified_at: DateTime.add(DateTime.utc_now(), -60)]
    )

    newer = insert(:session, user: user, expires_at: DateTime.add(DateTime.utc_now(), 86_400))
    {:ok, :ok} = TFASessions.record_verified!(user, newer.id)
    target = insert(:oauth_session, user: user, client_id: insert(:oauth_client).client_id)
    :ok = TFASessions.copy!(newer.id, target.id, user)
    assert OrganizationAuth.check(organization, user, nil, target.id) == :ok
    {:ok, _} = Hexpm.UserSessions.revoke(newer)
    assert OrganizationAuth.check(organization, user, nil, target.id) == {:error, :tfa_required}
    assert OrganizationAuth.check(organization, user, nil, browser_id) == :ok
    {:ok, request} = SSO.request_authorization(user, target.id, [organization.name])

    response =
      browser
      |> recycle()
      |> post("/organizations/authorize", %{
        code: request.raw_code,
        organization: organization.name
      })

    response = response |> recycle() |> get(redirected_to(response))
    assert redirected_to(response) == "/dashboard"
    refute Phoenix.Flash.get(response.assigns.flash, :error)
    refute SSO.get_authorization(request.raw_code, user)
    assert OrganizationAuth.check(organization, user, nil, target.id) == :ok
    copied = Repo.get!(Hexpm.UserSession, target.id)
    assert copied.tfa_verified_at == Repo.get!(Hexpm.UserSession, browser_id).tfa_verified_at
    assert copied.tfa_source_session_id == browser_id
    assert Repo.get!(Hexpm.UserSession, target.id).expires_at == target.expires_at
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

  test "shared authorization uses proof from successful sudo TOTP verification" do
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
      |> post("/sudo", %{type: "tfa", code: Hexpm.Accounts.TFA.time_based_token(user.tfa.secret)})

    assert redirected_to(conn) =~ "/organizations/authorize"
    assert HexpmWeb.Plugs.Sudo.sudo_active?(conn)
    assert TFASessions.proof(user, conn.assigns.current_session.id)
    conn = conn |> recycle() |> get(redirected_to(conn))
    assert html_response(conn, 200) =~ "2FA verification required"

    conn =
      conn
      |> recycle()
      |> post("/organizations/authorize", %{
        code: request.raw_code,
        organization: organization.name
      })

    assert redirected_to(conn) =~ "/organizations/authorize"
    conn = conn |> recycle() |> get(redirected_to(conn))
    assert redirected_to(conn) == "/dashboard"
    assert TFASessions.proof(user, target.id)
  end
end
