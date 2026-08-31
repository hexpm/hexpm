defmodule HexpmWeb.Dashboard.OrganizationSSOControllerTest do
  use HexpmWeb.ConnCase
  use Oban.Testing, repo: Hexpm.RepoBase

  alias Hexpm.Accounts.{AuditLogs, OrganizationDomain, OrganizationDomains, SSO}
  alias Hexpm.Accounts.SSO.{Connection, Error, OIDC}
  alias Hexpm.Emails.{OutboxEntry, OutboxWorker}

  defmodule EmptyResolver do
    def lookup(_domain), do: []
  end

  setup :verify_on_exit!

  setup do
    organization = insert(:organization)
    admin = insert(:user)
    member = insert(:user)
    insert(:organization_user, organization: organization, user: admin, role: "admin")
    insert(:organization_user, organization: organization, user: member, role: "read")
    enable_beta_for(organization)
    stub(Hexpm.Billing.Mock, :get, fn _organization, _opts -> nil end)

    %{admin: admin, member: member, organization: organization}
  end

  test "shows the admin-only SSO tab without rendering stored secrets", context do
    insert(:organization_sso_connection,
      organization: context.organization,
      client_secret: "stored-client-secret"
    )

    html =
      build_conn()
      |> test_login(context.admin)
      |> get("/dashboard/orgs/#{context.organization.name}/sso")
      |> html_response(200)

    assert html =~ "Single sign-on"
    assert html =~ "Redirect URI"
    assert html =~ "Okta is the documented pilot integration"
    assert html =~ "Required scopes"
    assert html =~ "openid email"
    refute html =~ "stored-client-secret"

    {:ok, document} = Floki.parse_document(html)

    assert [_link] =
             Floki.find(document, ~s(a[href="/docs/organization-sso"]))

    for path <- [
          "/dashboard/orgs/#{context.organization.name}/policies",
          "/dashboard/orgs/#{context.organization.name}/sso"
        ] do
      assert [tab] = Floki.find(document, ~s(#org-tab-nav a[href="#{path}"]))
      assert Floki.text(tab) =~ "NEW"
    end

    conn =
      build_conn()
      |> test_login(context.member)
      |> get("/dashboard/orgs/#{context.organization.name}/sso")

    assert response(conn, 400)
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "permission"
  end

  test "shows the connection test and enabled status in the provider configuration header",
       context do
    connection =
      insert(:organization_sso_connection,
        organization: context.organization,
        configured_by_user_id: context.admin.id,
        tested_at: nil,
        enabled_at: nil
      )

    status = connection_status(context)

    assert Floki.text(status) |> String.trim() == "Not tested"

    connection =
      connection
      |> Ecto.Changeset.change(tested_at: DateTime.utc_now())
      |> Repo.update!()

    status = connection_status(context)

    assert Floki.text(status) |> String.trim() == "Tested, disabled"

    connection
    |> Ecto.Changeset.change(enabled_at: DateTime.utc_now())
    |> Repo.update!()

    status = connection_status(context)

    assert Floki.text(status) |> String.trim() == "Enabled"
  end

  test "links linked accounts to user profiles", context do
    connection =
      insert(:organization_sso_connection,
        organization: context.organization,
        enabled_at: DateTime.utc_now()
      )

    insert(:organization_sso_identity,
      connection: connection,
      organization: context.organization,
      user: context.member
    )

    html =
      build_conn()
      |> test_login(context.admin)
      |> get("/dashboard/orgs/#{context.organization.name}/sso")
      |> html_response(200)

    {:ok, document} = Floki.parse_document(html)

    assert [_link] =
             Floki.find(
               document,
               ~s(#sso-linked-accounts a[href="/users/#{context.member.username}"])
             )
  end

  test "the runtime gate hides setup and action routes", context do
    config = Application.fetch_env!(:hexpm, :organization_sso)
    Application.put_env(:hexpm, :organization_sso, Keyword.put(config, :mode, :off))

    build_conn()
    |> test_login(context.admin)
    |> get("/dashboard/orgs/#{context.organization.name}/sso")
    |> response(404)

    build_conn()
    |> test_login(context.admin)
    |> post("/dashboard/orgs/#{context.organization.name}/sso", %{
      sso: %{issuer: "https://identity.example.com", client_id: "id", client_secret: "secret"}
    })
    |> response(404)
  end

  test "an empty beta allowlist keeps every organization SSO surface hidden", context do
    config = Application.fetch_env!(:hexpm, :organization_sso)

    app_env(
      :hexpm,
      :organization_sso,
      Keyword.merge(config, mode: :beta, beta_organizations: [])
    )

    html =
      build_conn()
      |> test_login(context.admin)
      |> get("/dashboard/orgs/#{context.organization.name}")
      |> html_response(200)

    {:ok, document} = Floki.parse_document(html)

    assert Floki.find(
             document,
             ~s(#org-tab-nav a[href="/dashboard/orgs/#{context.organization.name}/sso"])
           ) == []

    build_conn()
    |> test_login(context.admin)
    |> get("/dashboard/orgs/#{context.organization.name}/sso")
    |> response(404)

    build_conn()
    |> get("/sso/#{context.organization.name}")
    |> response(404)

    build_conn()
    |> get("/docs/organization-sso")
    |> response(404)
  end

  test "configures a provider-neutral connection", context do
    expect(OIDC.Mock, :discover, fn issuer ->
      assert issuer == "https://identity.example.com/oauth2/default"
      {:ok, metadata(issuer)}
    end)

    conn =
      build_conn()
      |> test_login(context.admin)
      |> post("/dashboard/orgs/#{context.organization.name}/sso", %{
        sso: %{
          issuer: "https://identity.example.com/oauth2/default",
          client_id: "client-id",
          client_secret: "client-secret"
        }
      })

    assert redirected_to(conn) == "/dashboard/orgs/#{context.organization.name}/sso"
    assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "saved"

    connection = Repo.get_by!(Connection, organization_id: context.organization.id)
    assert connection.issuer == "https://identity.example.com/oauth2/default"
    refute inspect(connection) =~ "client-secret"
  end

  test "does not log connection secrets from SSO routes", context do
    client_secret = "router-log-client-secret"

    expect(OIDC.Mock, :discover, fn issuer -> {:ok, metadata(issuer)} end)

    log =
      capture_debug_log(fn ->
        build_conn()
        |> test_login(context.admin)
        |> post("/dashboard/orgs/#{context.organization.name}/sso", %{
          sso: %{
            issuer: "https://identity.example.com/oauth2/default",
            client_id: "router-log-client-id",
            client_secret: client_secret
          }
        })
        |> response(302)
      end)

    # Something has to have been logged, or the refute below is asserting about
    # an empty string.
    assert log =~ "organization_sso_connections"
    refute log =~ client_secret
  end

  test "the settings page allows the provider origin in form-action", context do
    insert(:organization_sso_connection,
      organization: context.organization,
      configured_by_user_id: context.admin.id,
      tested_at: nil,
      enabled_at: nil
    )

    conn =
      build_conn()
      |> test_login(context.admin)
      |> get("/dashboard/orgs/#{context.organization.name}/sso")

    assert html_response(conn, 200)

    [csp] = get_resp_header(conn, "content-security-policy")
    assert csp =~ "form-action 'self' https://identity.example.com"
  end

  test "the settings page keeps form-action closed without a connection", context do
    conn =
      build_conn()
      |> test_login(context.admin)
      |> get("/dashboard/orgs/#{context.organization.name}/sso")

    assert html_response(conn, 200)

    [csp] = get_resp_header(conn, "content-security-policy")
    assert csp =~ "form-action 'self';"
  end

  test "tests, enables, and immediately disables a connection", context do
    connection =
      insert(:organization_sso_connection,
        organization: context.organization,
        configured_by_user_id: context.admin.id,
        tested_at: nil,
        enabled_at: nil
      )

    expect(OIDC.Mock, :authorization_uri, fn received_connection,
                                             transaction,
                                             redirect_uri,
                                             client_secret ->
      assert received_connection.id == connection.id
      assert client_secret == connection.client_secret
      send(self(), {:test_state, transaction.raw_state, redirect_uri})
      {:ok, "https://identity.example.com/authorize"}
    end)

    conn =
      build_conn()
      |> test_login(context.admin)
      |> post("/dashboard/orgs/#{context.organization.name}/sso/test", %{
        secret_slot: "active"
      })

    assert redirected_to(conn) == "https://identity.example.com/authorize"
    assert_receive {:test_state, state, redirect_uri}

    expect(OIDC.Mock, :exchange_code, fn _connection,
                                         transaction,
                                         "code",
                                         received_redirect_uri,
                                         _secret ->
      assert transaction.state_hash == :crypto.hash(:sha256, state)
      assert received_redirect_uri == redirect_uri

      {:ok,
       %{
         issuer: connection.issuer,
         subject: "00u-admin",
         email: List.first(context.admin.emails).email,
         jwks_document: nil
       }}
    end)

    conn = conn |> recycle() |> get("/sso/callback", %{state: state, code: "code"})
    assert redirected_to(conn) == "/dashboard/orgs/#{context.organization.name}/sso"
    assert Repo.get!(Connection, connection.id).tested_at

    conn =
      conn
      |> recycle()
      |> post("/dashboard/orgs/#{context.organization.name}/sso/enable")

    assert Repo.get!(Connection, connection.id).enabled_at

    conn =
      conn
      |> recycle()
      |> post("/dashboard/orgs/#{context.organization.name}/sso/disable")

    refute Repo.get!(Connection, connection.id).enabled_at
    assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "disabled immediately"
  end

  test "only the configuring administrator can start the active connection test", context do
    insert(:organization_sso_connection,
      organization: context.organization,
      configured_by_user_id: context.admin.id,
      tested_at: nil,
      enabled_at: nil
    )

    second_admin = insert(:user)

    insert(:organization_user,
      organization: context.organization,
      user: second_admin,
      role: "admin"
    )

    conn =
      build_conn()
      |> test_login(second_admin)
      |> post("/dashboard/orgs/#{context.organization.name}/sso/test", %{
        secret_slot: "active"
      })

    assert redirected_to(conn) == "/dashboard/orgs/#{context.organization.name}/sso"

    assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
             "The administrator who saved the configuration must complete its connection test. If that administrator is unavailable, disable SSO if needed and have a current administrator save the configuration again."

    refute Repo.one(SSO.Transaction)
  end

  test "an administrator can unlink an identity and notify the member", context do
    connection =
      insert(:organization_sso_connection,
        organization: context.organization,
        enabled_at: DateTime.utc_now()
      )

    identity =
      insert(:organization_sso_identity,
        connection: connection,
        organization: context.organization,
        user: context.member
      )

    linked_notification =
      insert(:email_outbox_entry,
        group_key: sso_group_key(connection, context.member),
        category: "sso.identity_linked"
      )

    mismatch_notification =
      insert(:email_outbox_entry,
        group_key: sso_group_key(connection, context.member),
        category: "sso.email_mismatch"
      )

    conn =
      build_conn()
      |> test_login(context.admin)
      |> post("/dashboard/orgs/#{context.organization.name}/sso/unlink", %{
        user_id: to_string(context.member.id)
      })

    refute Repo.get(Hexpm.Accounts.SSO.Identity, identity.id)
    refute Repo.get(OutboxEntry, linked_notification.id)
    refute Repo.get(OutboxEntry, mismatch_notification.id)
    assert redirected_to(conn) == "/dashboard/orgs/#{context.organization.name}/sso"
    assert_enqueued(worker: OutboxWorker)

    assert %OutboxEntry{
             category: "sso.identity_unlinked",
             group_key: group_key
           } = Repo.one!(OutboxEntry)

    assert group_key == sso_group_key(connection, context.member)

    unlink_log =
      Enum.find(AuditLogs.all_by(context.organization), &(&1.action == "sso.identity.unlink"))

    assert unlink_log.user_id == context.admin.id
    assert unlink_log.params["user_id"] == context.member.id
  end

  test "an unlink request without an organization identity does not notify another user",
       context do
    insert(:organization_sso_connection,
      organization: context.organization,
      enabled_at: DateTime.utc_now()
    )

    conn =
      build_conn()
      |> test_login(context.admin)
      |> post("/dashboard/orgs/#{context.organization.name}/sso/unlink", %{
        user_id: to_string(context.member.id)
      })

    assert response(conn, 404)
    refute_enqueued(worker: OutboxWorker)
  end

  defp sso_group_key(connection, user), do: "sso:#{connection.id}:#{user.id}"

  test "diagnostics are capped and stable", context do
    connection =
      insert(:organization_sso_connection,
        organization: context.organization,
        enabled_at: DateTime.utc_now()
      )

    for _attempt <- 1..25 do
      assert {:ok, _failure} =
               SSO.record_failure(connection, %Error{stage: :claims, code: :issuer_mismatch})
    end

    assert length(SSO.failures(connection)) == 20

    html =
      build_conn()
      |> test_login(context.admin)
      |> get("/dashboard/orgs/#{context.organization.name}/sso")
      |> html_response(200)

    assert html =~ "claims"
    assert html =~ "issuer_mismatch"
  end

  test "lets the browser follow the form through to the authorization endpoint", context do
    insert(:organization_sso_connection,
      organization: context.organization,
      issuer: "https://issuer.example",
      discovery_document: %{
        "issuer" => "https://issuer.example",
        "authorization_endpoint" => "https://login.example/oauth2/authorize"
      }
    )

    conn =
      build_conn()
      |> test_login(context.admin)
      |> get("/dashboard/orgs/#{context.organization.name}/sso")

    assert html_response(conn, 200)

    [csp] = get_resp_header(conn, "content-security-policy")

    # The POST redirect goes to the authorization endpoint, which nothing
    # requires to share an origin with the issuer.
    assert csp =~ "form-action 'self' https://login.example"
    refute csp =~ "https://issuer.example"
  end

  test "lists the personal keys that reach the organization on the SSO tab", context do
    insert(:organization_sso_connection, organization: context.organization)

    Hexpm.Accounts.Keys.create(
      context.member,
      %{
        name: "laptop",
        permissions: [%{"domain" => "repository", "resource" => context.organization.name}]
      },
      audit: audit_data(context.member)
    )

    Hexpm.Accounts.Keys.create(
      context.member,
      %{name: "everything", permissions: [%{"domain" => "repositories"}]},
      audit: audit_data(context.member)
    )

    # `api:write` plus membership publishes and changes owners, so this key
    # reaches the organization without naming it anywhere.
    Hexpm.Accounts.Keys.create(
      context.member,
      %{name: "ci", permissions: [%{"domain" => "api", "resource" => "write"}]},
      audit: audit_data(context.member)
    )

    html =
      build_conn()
      |> test_login(context.admin)
      |> get("/dashboard/orgs/#{context.organization.name}/sso")
      |> html_response(200)

    assert html =~ "Personal API keys that reach this organization"

    assert html =~
             "records when it was last used but not what it was used for"

    {:ok, document} = Floki.parse_document(html)

    rows =
      document
      |> Floki.find("#sso-enforcement table tbody tr")
      |> Enum.map(fn row ->
        row |> Floki.find("td") |> Enum.map(&(&1 |> Floki.text() |> String.trim()))
      end)

    assert rows == [
             [context.member.username, "ci", "Through the key's API access", "Never"],
             [context.member.username, "everything", "Through every repository", "Never"],
             [context.member.username, "laptop", "Named in the key", "Never"]
           ]
  end

  test "shows the exemption list and the residual bypasses during the grace period", context do
    insert(:organization_sso_connection,
      organization: context.organization,
      tested_at: DateTime.utc_now(),
      enabled_at: DateTime.utc_now(),
      enforcement_mode: "required",
      required_at: DateTime.add(DateTime.utc_now(), 9 * 24 * 60 * 60, :second)
    )

    {:ok, _member} =
      SSO.set_member_enforcement(context.organization, context.member, "exempt",
        audit: audit_data(context.admin)
      )

    conn = build_conn() |> test_login(context.admin)

    # The activation checklist says review the exemptions and then set the date.
    # Doing it the other way round leaves the mode in force reading as pilot.
    members = conn |> get("/dashboard/orgs/#{context.organization.name}/members")
    members_html = html_response(members, 200)

    assert members_html =~ "Exempt from SSO (1)"
    assert members_html =~ context.member.username
    assert members_html =~ "Enforced on the date"

    sso_html =
      conn
      |> get("/dashboard/orgs/#{context.organization.name}/sso")
      |> html_response(200)

    assert sso_html =~ "Exempt members (1)"
    assert sso_html =~ "Billing and this page"
    assert sso_html =~ "Organization API keys"
  end

  test "does not claim every member goes through the provider when nobody is exempt", context do
    insert(:organization_sso_connection,
      organization: context.organization,
      tested_at: DateTime.utc_now(),
      enabled_at: DateTime.utc_now(),
      enforcement_mode: "required",
      required_at: DateTime.add(DateTime.utc_now(), 9 * 24 * 60 * 60, :second)
    )

    html =
      build_conn()
      |> test_login(context.admin)
      |> get("/dashboard/orgs/#{context.organization.name}/members")
      |> html_response(200)

    assert html =~ "Nobody is exempt."
    assert html =~ "Organization API keys and, unless you block them, personal API keys"
  end

  test "takes a fresh password before enforcement is turned down", context do
    connection =
      insert(:organization_sso_connection,
        organization: context.organization,
        tested_at: DateTime.utc_now(),
        enabled_at: DateTime.utc_now(),
        enforcement_mode: "required",
        required_at: DateTime.utc_now()
      )

    conn =
      build_conn()
      |> test_login(context.admin,
        sudo_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -5, :minute)
      )
      |> post("/dashboard/orgs/#{context.organization.name}/sso/enforcement", %{
        "enforcement" => %{"enforcement_mode" => "optional", "personal_keys" => "allow"}
      })

    assert redirected_to(conn) == "/sudo"
    assert Repo.get!(Connection, connection.id).enforcement_mode == "required"
  end

  test "turns enforcement down for an administrator who just authenticated", context do
    connection =
      insert(:organization_sso_connection,
        organization: context.organization,
        tested_at: DateTime.utc_now(),
        enabled_at: DateTime.utc_now(),
        enforcement_mode: "required",
        required_at: DateTime.utc_now()
      )

    conn =
      build_conn()
      |> test_login(context.admin)
      |> post("/dashboard/orgs/#{context.organization.name}/sso/enforcement", %{
        "enforcement" => %{"enforcement_mode" => "optional", "personal_keys" => "allow"}
      })

    assert redirected_to(conn) == "/dashboard/orgs/#{context.organization.name}/sso"
    assert Repo.get!(Connection, connection.id).enforcement_mode == "optional"
  end

  describe "SCIM provisioning" do
    setup context do
      connection = insert(:organization_sso_connection, organization: context.organization)
      Map.put(context, :connection, connection)
    end

    test "generating a token shows it exactly once", context do
      conn =
        build_conn()
        |> test_login(context.admin)
        |> post("/dashboard/orgs/#{context.organization.name}/sso/scim/generate", %{
          "scim" => %{"scim_seat_policy" => "block", "scim_role" => "read"}
        })

      assert redirected_to(conn) == "/dashboard/orgs/#{context.organization.name}/sso"

      html =
        conn
        |> recycle()
        |> get("/dashboard/orgs/#{context.organization.name}/sso")
        |> html_response(200)

      assert html =~ "Copy the token now"
      assert [token] = Regex.run(~r/<code[^>]*>\s*([0-9a-f]{32})\s*<\/code>/, html) |> tl()
      assert {:ok, _connection} = SSO.scim_auth(token)

      html =
        build_conn()
        |> test_login(context.admin)
        |> get("/dashboard/orgs/#{context.organization.name}/sso")
        |> html_response(200)

      refute html =~ "Copy the token now"
      refute html =~ token
    end

    test "the one-time token never renders on another organization", context do
      other = insert(:organization)
      insert(:organization_user, organization: other, user: context.admin, role: "admin")
      insert(:organization_sso_connection, organization: other)

      config = Application.fetch_env!(:hexpm, :organization_sso)

      app_env(
        :hexpm,
        :organization_sso,
        Keyword.merge(config,
          mode: :beta,
          beta_organizations: [context.organization.name, other.name]
        )
      )

      conn =
        build_conn()
        |> test_login(context.admin)
        |> post("/dashboard/orgs/#{context.organization.name}/sso/scim/generate", %{
          "scim" => %{"scim_seat_policy" => "block", "scim_role" => "read"}
        })

      html =
        conn
        |> recycle()
        |> get("/dashboard/orgs/#{other.name}/sso")
        |> html_response(200)

      refute html =~ "Copy the token now"
    end

    test "generating without the seat policy is refused", context do
      conn =
        build_conn()
        |> test_login(context.admin)
        |> post("/dashboard/orgs/#{context.organization.name}/sso/scim/generate", %{
          "scim" => %{"scim_role" => "read"}
        })

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~
               "Choose what happens when the seats run out"

      refute Connection.scim_enabled?(Repo.get!(Connection, context.connection.id))
    end

    test "settings save and token delete work while provisioning is on", context do
      {:ok, _connection} =
        SSO.generate_scim_token(
          context.organization,
          %{"scim_seat_policy" => "block", "scim_role" => "read"},
          audit: audit_data(context.admin)
        )

      conn =
        build_conn()
        |> test_login(context.admin)
        |> post("/dashboard/orgs/#{context.organization.name}/sso/scim", %{
          "scim" => %{"scim_seat_policy" => "expand", "scim_role" => "write"}
        })

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Provisioning settings saved"
      stored = Repo.get!(Connection, context.connection.id)
      assert stored.scim_seat_policy == "expand"
      assert stored.scim_role == "write"

      conn =
        build_conn()
        |> test_login(context.admin)
        |> post("/dashboard/orgs/#{context.organization.name}/sso/scim/delete")

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Provisioning is off"
      refute Connection.scim_enabled?(Repo.get!(Connection, context.connection.id))
    end

    test "members cannot touch provisioning", context do
      conn =
        build_conn()
        |> test_login(context.member)
        |> post("/dashboard/orgs/#{context.organization.name}/sso/scim/generate", %{
          "scim" => %{"scim_seat_policy" => "block", "scim_role" => "read"}
        })

      assert response(conn, 403)
    end
  end

  defp enable_beta_for(organization) do
    config = Application.fetch_env!(:hexpm, :organization_sso)

    app_env(
      :hexpm,
      :organization_sso,
      Keyword.merge(config, mode: :beta, beta_organizations: [organization.name])
    )
  end

  defp connection_status(context) do
    html =
      build_conn()
      |> test_login(context.admin)
      |> get("/dashboard/orgs/#{context.organization.name}/sso")
      |> html_response(200)

    {:ok, document} = Floki.parse_document(html)
    [status] = Floki.find(document, "section > div:first-child > #sso-connection-status")
    status
  end

  describe "verified domains" do
    test "adds a domain and shows the record to publish", context do
      conn =
        build_conn()
        |> test_login(context.admin)
        |> post("/dashboard/orgs/#{context.organization.name}/sso/domains", %{
          "domain" => %{"domain" => "Example.com"}
        })

      assert redirected_to(conn) == "/dashboard/orgs/#{context.organization.name}/sso"

      assert [domain] = OrganizationDomains.all(context.organization)
      assert domain.domain == "example.com"

      html =
        build_conn()
        |> test_login(context.admin)
        |> get("/dashboard/orgs/#{context.organization.name}/sso")
        |> html_response(200)

      assert html =~ "example.com"
      assert html =~ OrganizationDomain.record_value(domain)
    end

    test "rejects a domain that is not one", context do
      conn =
        build_conn()
        |> test_login(context.admin)
        |> post("/dashboard/orgs/#{context.organization.name}/sso/domains", %{
          "domain" => %{"domain" => "not a domain"}
        })

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "is not a valid domain name"
      assert OrganizationDomains.all(context.organization) == []
    end

    test "says what to do when the record is not published yet", context do
      # Stubbed rather than left to real DNS: another test file swaps this
      # resolver globally, and the answer has to be "the resolver said no",
      # not "the resolver did not answer".
      app_env(:hexpm, :domain_dns_resolver, EmptyResolver)
      {:ok, domain} = add_domain(context, "example.com")

      conn =
        build_conn()
        |> test_login(context.admin)
        |> post("/dashboard/orgs/#{context.organization.name}/sso/domains/verify", %{
          "domain_id" => to_string(domain.id)
        })

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "No matching TXT record"
      refute OrganizationDomain.verified?(Hexpm.Repo.get!(OrganizationDomain, domain.id))
    end

    test "removes a domain", context do
      {:ok, domain} = add_domain(context, "example.com")

      conn =
        build_conn()
        |> test_login(context.admin)
        |> post("/dashboard/orgs/#{context.organization.name}/sso/domains/remove", %{
          "domain_id" => to_string(domain.id)
        })

      assert redirected_to(conn) == "/dashboard/orgs/#{context.organization.name}/sso"
      assert OrganizationDomains.all(context.organization) == []
    end

    test "will not touch another organization's domain", context do
      other = insert(:organization)
      insert(:organization_user, organization: other, user: context.admin, role: "admin")

      {:ok, domain} =
        OrganizationDomains.add(other, %{"domain" => "example.com"}, context.admin,
          audit: audit_data(context.admin)
        )

      build_conn()
      |> test_login(context.admin)
      |> post("/dashboard/orgs/#{context.organization.name}/sso/domains/remove", %{
        "domain_id" => to_string(domain.id)
      })
      |> response(404)

      assert [_domain] = OrganizationDomains.all(other)
    end

    test "a read member cannot add a domain", context do
      conn =
        build_conn()
        |> test_login(context.member)
        |> post("/dashboard/orgs/#{context.organization.name}/sso/domains", %{
          "domain" => %{"domain" => "example.com"}
        })

      assert response(conn, 403)
      assert OrganizationDomains.all(context.organization) == []
    end
  end

  describe "just-in-time membership" do
    test "will not turn on without a verified domain", context do
      insert(:organization_sso_connection, organization: context.organization)

      conn =
        build_conn()
        |> test_login(context.admin)
        |> post("/dashboard/orgs/#{context.organization.name}/sso/jit", %{
          "jit" => %{"jit_seat_policy" => "block", "jit_role" => "read"}
        })

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Verify a domain"
      refute Connection.jit_enabled?(SSO.get_connection(context.organization))
    end

    test "turns on once a domain is verified and says what it will do", context do
      insert(:organization_sso_connection, organization: context.organization)
      verify_domain(context)

      conn =
        build_conn()
        |> test_login(context.admin)
        |> post("/dashboard/orgs/#{context.organization.name}/sso/jit", %{
          "jit" => %{"jit_seat_policy" => "expand", "jit_role" => "write"}
        })

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "grows by a seat"

      connection = SSO.get_connection(context.organization)
      assert connection.jit_seat_policy == "expand"
      assert connection.jit_role == "write"
    end

    test "a read member cannot change it", context do
      insert(:organization_sso_connection, organization: context.organization)
      verify_domain(context)

      conn =
        build_conn()
        |> test_login(context.member)
        |> post("/dashboard/orgs/#{context.organization.name}/sso/jit", %{
          "jit" => %{"jit_seat_policy" => "block", "jit_role" => "read"}
        })

      assert response(conn, 403)
      refute Connection.jit_enabled?(SSO.get_connection(context.organization))
    end
  end

  defp verify_domain(context) do
    {:ok, domain} =
      OrganizationDomains.add(context.organization, %{"domain" => "example.com"}, context.admin,
        audit: audit_data(context.admin)
      )

    domain
    |> Ecto.Changeset.change(verified_at: DateTime.utc_now())
    |> Hexpm.Repo.update!()
  end

  defp add_domain(context, domain) do
    OrganizationDomains.add(context.organization, %{"domain" => domain}, context.admin,
      audit: audit_data(context.admin)
    )
  end

  defp metadata(issuer) do
    %{
      discovery_document: %{
        "issuer" => issuer,
        "authorization_endpoint" => "https://identity.example.com/authorize",
        "token_endpoint" => "https://identity.example.com/token",
        "jwks_uri" => "https://identity.example.com/keys"
      },
      jwks_document: %{"keys" => [%{"kty" => "RSA", "kid" => "key-1"}]},
      discovery_expires_at: DateTime.add(DateTime.utc_now(), 3_600, :second),
      jwks_expires_at: DateTime.add(DateTime.utc_now(), 3_600, :second),
      metadata_expires_at: DateTime.add(DateTime.utc_now(), 3_600, :second)
    }
  end
end
