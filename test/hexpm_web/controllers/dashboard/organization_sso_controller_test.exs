defmodule HexpmWeb.Dashboard.OrganizationSSOControllerTest do
  use HexpmWeb.ConnCase
  use Oban.Testing, repo: Hexpm.RepoBase

  import ExUnit.CaptureLog

  alias Hexpm.Accounts.SSO
  alias Hexpm.Accounts.SSO.{Connection, Error, Notification, OIDC}
  alias Hexpm.Emails.SSONotificationWorker

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

    conn =
      build_conn()
      |> test_login(context.member)
      |> get("/dashboard/orgs/#{context.organization.name}/sso")

    assert response(conn, 400)
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "permission"
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
      insert(:organization_sso_notification,
        connection: connection,
        user: context.member,
        kind: "identity_linked"
      )

    mismatch_notification =
      insert(:organization_sso_notification,
        connection: connection,
        user: context.member,
        kind: "email_mismatch",
        provider_email: "renamed@identity.example.com"
      )

    conn =
      build_conn()
      |> test_login(context.admin)
      |> post("/dashboard/orgs/#{context.organization.name}/sso/unlink", %{
        user_id: to_string(context.member.id)
      })

    refute Repo.get(Hexpm.Accounts.SSO.Identity, identity.id)
    refute Repo.get(Notification, linked_notification.id)
    refute Repo.get(Notification, mismatch_notification.id)
    assert redirected_to(conn) == "/dashboard/orgs/#{context.organization.name}/sso"
    assert_enqueued(worker: SSONotificationWorker)
    assert %Notification{kind: "identity_unlinked"} = Repo.one!(Notification)
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
    refute_enqueued(worker: SSONotificationWorker)
  end

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
