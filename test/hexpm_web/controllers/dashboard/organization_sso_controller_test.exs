defmodule HexpmWeb.Dashboard.OrganizationSSOControllerTest do
  use HexpmWeb.ConnCase
  use Oban.Testing, repo: Hexpm.RepoBase

  import ExUnit.CaptureLog

  alias Hexpm.Accounts.{AuditLogs, SSO}
  alias Hexpm.Accounts.SSO.{Connection, Error, OIDC}
  alias Hexpm.Emails.{OutboxEntry, OutboxWorker}

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
      capture_log([level: :debug], fn ->
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

    refute log =~ client_secret
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
        ordering_key: sso_ordering_key(connection, context.member),
        category: "sso.identity_linked"
      )

    mismatch_notification =
      insert(:email_outbox_entry,
        ordering_key: sso_ordering_key(connection, context.member),
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
             ordering_key: ordering_key
           } = Repo.one!(OutboxEntry)

    assert ordering_key == sso_ordering_key(connection, context.member)

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

  defp sso_ordering_key(connection, user), do: "sso:#{connection.id}:#{user.id}"

  test "diagnostics are capped, stable, and redact all supplied details", context do
    connection =
      insert(:organization_sso_connection,
        organization: context.organization,
        enabled_at: DateTime.utc_now()
      )

    for _attempt <- 1..25 do
      assert {:ok, _failure} =
               SSO.record_failure(connection, %Error{
                 stage: :claims,
                 code: :issuer_mismatch,
                 details: %{reason: "stored-client-secret", token: "raw-token"}
               })
    end

    assert length(SSO.failures(connection)) == 20

    html =
      build_conn()
      |> test_login(context.admin)
      |> get("/dashboard/orgs/#{context.organization.name}/sso")
      |> html_response(200)

    assert html =~ "claims"
    assert html =~ "issuer_mismatch"
    refute html =~ "stored-client-secret"
    refute html =~ "raw-token"
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
