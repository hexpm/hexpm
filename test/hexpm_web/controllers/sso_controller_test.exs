defmodule HexpmWeb.SSOControllerTest do
  use HexpmWeb.ConnCase
  use Oban.Testing, repo: Hexpm.RepoBase

  import ExUnit.CaptureLog

  alias Hexpm.Accounts.{AuditLogs, SSO}
  alias Hexpm.Accounts.SSO.{Identity, Notification, OIDC}
  alias Hexpm.Emails.SSONotificationWorker
  alias HexpmWeb.Plugs.Attack

  setup :verify_on_exit!

  setup do
    organization = insert(:organization)
    member = insert(:user)
    insert(:organization_user, organization: organization, user: member, role: "admin")
    enable_beta_for(organization)

    connection =
      insert(:organization_sso_connection,
        organization: organization,
        tested_at: DateTime.utc_now(),
        enabled_at: DateTime.utc_now()
      )

    %{connection: connection, member: member, organization: organization}
  end

  test "does not log callback authorization parameters", _context do
    state = "router-log-state-value"
    code = "router-log-code-value"

    log =
      capture_log([level: :debug], fn ->
        build_conn()
        |> get("/sso/callback", %{state: state, code: code})
        |> response(302)
      end)

    refute log =~ state
    refute log =~ code
  end

  test "first login proves the existing member account before an explicit link", context do
    expect_authorization_request(context.connection)

    conn = get(build_conn(), "/sso/#{context.organization.name}")
    assert redirected_to(conn) =~ "https://identity.example.com/authorize"
    assert_receive {:sso_state, state, redirect_uri}

    member_email = List.first(context.member.emails).email
    expect_code_exchange(context.connection, state, redirect_uri, member_email)

    conn =
      conn
      |> recycle()
      |> get("/sso/callback", %{state: state, code: "authorization-code"})

    assert redirected_to(conn) == "/login?return=/sso/link"
    assert %{"transaction_id" => _, "token" => _} = get_session(conn, "pending_sso_link")
    assert Repo.all(Identity) == []

    mock_pwned()

    conn =
      conn
      |> recycle()
      |> post("/login", %{
        username: context.member.username,
        password: "password",
        return: "/sso/link"
      })

    assert redirected_to(conn) == "/sso/link"

    html = conn |> recycle() |> get("/sso/link") |> html_response(200)
    assert html =~ "Connect organization SSO"
    assert html =~ context.member.username
    assert html =~ member_email
    assert html =~ "not used to match accounts or grant membership"

    conn = conn |> recycle() |> post("/sso/link")

    assert redirected_to(conn) == "/dashboard/orgs/#{context.organization.name}"
    refute get_session(conn, "pending_sso_link")

    assert %Identity{user_id: user_id, organization_id: organization_id} =
             Repo.one!(Identity)

    assert user_id == context.member.id
    assert organization_id == context.organization.id
    assert_enqueued(worker: SSONotificationWorker)
    assert %Notification{kind: "identity_linked"} = Repo.one!(Notification)

    link_log =
      Enum.find(AuditLogs.all_by(context.organization), &(&1.action == "sso.identity.link"))

    assert link_log.user_id == context.member.id
    assert link_log.params["user_id"] == context.member.id
  end

  test "a nonmember account proof is rejected with actionable user diagnostics", context do
    outsider = insert(:user)
    conn = begin_pending_link(context)
    %{"transaction_id" => transaction_id} = get_session(conn, "pending_sso_link")
    mock_pwned()

    conn =
      conn
      |> recycle()
      |> post("/login", %{
        username: outsider.username,
        password: "password",
        return: "/sso/link"
      })

    assert redirected_to(conn) == "/users/#{outsider.username}"
    assert get_session(conn, "session_token")
    refute get_session(conn, "pending_sso_link")
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "not a member"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Ask an administrator"

    transaction = Repo.get!(SSO.Transaction, transaction_id)
    assert transaction.cancelled_at
    assert transaction.subject == nil
    assert transaction.provider_email == nil

    assert [%{stage: "link", code: "not_member", user: failure_user}] =
             SSO.failures(context.connection)

    assert failure_user.id == outsider.id

    stub(Hexpm.Billing.Mock, :get, fn _organization, _opts -> nil end)

    html =
      build_conn()
      |> test_login(context.member)
      |> get("/dashboard/orgs/#{context.organization.name}/sso")
      |> html_response(200)

    assert html =~ "The Hexpm account is not a member of the organization"
    assert html =~ outsider.username
  end

  test "an existing browser session does not satisfy first-link account proof", context do
    expect_authorization_request(context.connection)

    conn = build_conn() |> test_login(context.member) |> get("/sso/#{context.organization.name}")
    assert_receive {:sso_state, state, redirect_uri}
    expect_code_exchange(context.connection, state, redirect_uri, nil)

    conn =
      conn
      |> recycle()
      |> get("/sso/callback", %{state: state, code: "authorization-code"})

    assert redirected_to(conn) == "/login?return=/sso/link"

    conn = conn |> recycle() |> get("/sso/link")
    assert redirected_to(conn) == "/login?return=/sso/link"
    assert Repo.all(Identity) == []
  end

  test "cancelling a proved link does not start another SSO transaction", context do
    expect_authorization_request(context.connection)
    conn = get(build_conn(), "/sso/#{context.organization.name}")
    assert_receive {:sso_state, state, redirect_uri}
    expect_code_exchange(context.connection, state, redirect_uri, nil)

    conn =
      conn
      |> recycle()
      |> get("/sso/callback", %{state: state, code: "authorization-code"})

    mock_pwned()

    conn =
      conn
      |> recycle()
      |> post("/login", %{
        username: context.member.username,
        password: "password",
        return: "/sso/link"
      })

    transaction_count = Repo.aggregate(SSO.Transaction, :count)
    conn = conn |> recycle() |> post("/sso/link/cancel")

    assert redirected_to(conn) == "/users/#{context.member.username}"
    refute get_session(conn, "pending_sso_link")
    assert Repo.aggregate(SSO.Transaction, :count) == transaction_count
  end

  test "a connection disabled before password proof clears the stale link", context do
    conn = begin_pending_link(context)
    Repo.update!(Ecto.Changeset.change(context.connection, enabled_at: nil))
    assert_stale_link_is_cleared_after_password(conn, context)
  end

  test "a configuration changed before password proof clears the stale link", context do
    conn = begin_pending_link(context)

    Repo.update!(
      Ecto.Changeset.change(context.connection, version: context.connection.version + 1)
    )

    assert_stale_link_is_cleared_after_password(conn, context)
  end

  test "a feature disabled before password proof clears the stale link", context do
    conn = begin_pending_link(context)
    config = Application.fetch_env!(:hexpm, :organization_sso)
    Application.put_env(:hexpm, :organization_sso, Keyword.put(config, :mode, :off))
    assert_stale_link_is_cleared_after_password(conn, context)
  end

  test "callback state is bound to the browser that started the transaction", context do
    expect_authorization_request(context.connection)

    initiating_conn = get(build_conn(), "/sso/#{context.organization.name}")
    assert_receive {:sso_state, state, _redirect_uri}

    foreign_conn = get(build_conn(), "/sso/callback", %{state: state, code: "stolen-code"})
    assert redirected_to(foreign_conn) == "/login"
    assert SSO.get_transaction_by_state(state)

    assert get_session(initiating_conn, "sso_states") == [state]
  end

  test "TFA must finish before first-link account proof is recorded", context do
    member = insert(:user_with_tfa)
    insert(:organization_user, organization: context.organization, user: member, role: "read")
    expect_authorization_request(context.connection)

    conn = get(build_conn(), "/sso/#{context.organization.name}")
    assert_receive {:sso_state, state, redirect_uri}
    expect_code_exchange(context.connection, state, redirect_uri, nil)

    conn =
      conn
      |> recycle()
      |> get("/sso/callback", %{state: state, code: "authorization-code"})

    %{"transaction_id" => transaction_id} = get_session(conn, "pending_sso_link")
    mock_pwned()

    conn =
      conn
      |> recycle()
      |> post("/login", %{username: member.username, password: "password", return: "/sso/link"})

    assert redirected_to(conn) == "/tfa"
    assert Repo.get!(SSO.Transaction, transaction_id).user_id == nil

    code = Hexpm.Accounts.TFA.time_based_token(member.tfa.secret)
    conn = conn |> recycle() |> post("/tfa", %{code: code})

    assert redirected_to(conn) == "/sso/link"
    assert Repo.get!(SSO.Transaction, transaction_id).user_id == member.id
  end

  test "TFA recovery can finish first-link account proof", context do
    member = insert(:user_with_tfa)
    insert(:organization_user, organization: context.organization, user: member, role: "read")
    expect_authorization_request(context.connection)

    conn = get(build_conn(), "/sso/#{context.organization.name}")
    assert_receive {:sso_state, state, redirect_uri}
    expect_code_exchange(context.connection, state, redirect_uri, nil)

    conn =
      conn
      |> recycle()
      |> get("/sso/callback", %{state: state, code: "authorization-code"})

    %{"transaction_id" => transaction_id} = get_session(conn, "pending_sso_link")
    mock_pwned()

    conn =
      conn
      |> recycle()
      |> post("/login", %{username: member.username, password: "password", return: "/sso/link"})

    assert redirected_to(conn) == "/tfa"

    conn =
      conn
      |> recycle()
      |> post("/tfa/recovery", %{"code" => "1234-1234-1234-1234"})

    assert redirected_to(conn) == "/sso/link"
    assert Repo.get!(SSO.Transaction, transaction_id).user_id == member.id
  end

  test "an already-linked GitHub account can prove first-link control", context do
    insert(:user_provider,
      user: context.member,
      provider: "github",
      provider_uid: "sso-github-proof"
    )

    expect_authorization_request(context.connection)
    conn = get(build_conn(), "/sso/#{context.organization.name}")
    assert_receive {:sso_state, state, redirect_uri}
    expect_code_exchange(context.connection, state, redirect_uri, nil)

    conn =
      conn
      |> recycle()
      |> get("/sso/callback", %{state: state, code: "authorization-code"})

    pending = get_session(conn, "pending_sso_link")

    conn =
      build_conn()
      |> mock_github_auth_success(
        "sso-github-proof",
        List.first(context.member.emails).email
      )
      |> init_test_session(%{
        "pending_sso_link" => pending,
        "oauth_return" => "/sso/link"
      })
      |> HexpmWeb.AuthController.callback(%{})

    assert redirected_to(conn) == "/sso/link"
    assert Repo.get!(SSO.Transaction, pending["transaction_id"]).user_id == context.member.id
  end

  test "a nonmember GitHub account proof is rejected with actionable user diagnostics", context do
    outsider = insert(:user)

    insert(:user_provider,
      user: outsider,
      provider: "github",
      provider_uid: "sso-github-outsider"
    )

    conn = begin_pending_link(context)
    pending = get_session(conn, "pending_sso_link")

    conn =
      build_conn()
      |> mock_github_auth_success(
        "sso-github-outsider",
        List.first(outsider.emails).email
      )
      |> init_test_session(%{
        "pending_sso_link" => pending,
        "oauth_return" => "/sso/link"
      })
      |> HexpmWeb.AuthController.callback(%{})

    assert redirected_to(conn) == "/users/#{outsider.username}"
    assert get_session(conn, "session_token")
    refute get_session(conn, "pending_sso_link")
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "not a member"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Ask an administrator"

    transaction = Repo.get!(SSO.Transaction, pending["transaction_id"])
    assert transaction.cancelled_at
    assert transaction.subject == nil
    assert transaction.provider_email == nil

    assert [%{stage: "link", code: "not_member", user: failure_user}] =
             SSO.failures(context.connection)

    assert failure_user.id == outsider.id
  end

  test "an unlinked GitHub account cannot create or select a Hexpm account for linking",
       context do
    expect_authorization_request(context.connection)
    conn = get(build_conn(), "/sso/#{context.organization.name}")
    assert_receive {:sso_state, state, redirect_uri}
    expect_code_exchange(context.connection, state, redirect_uri, nil)

    conn =
      conn
      |> recycle()
      |> get("/sso/callback", %{state: state, code: "authorization-code"})

    pending = get_session(conn, "pending_sso_link")
    user_count = Repo.aggregate(Hexpm.Accounts.User, :count)

    conn =
      build_conn()
      |> mock_github_auth_success("unlinked-sso-github", "new@example.com")
      |> init_test_session(%{
        "pending_sso_link" => pending,
        "oauth_return" => "/sso/link"
      })
      |> HexpmWeb.AuthController.callback(%{})

    assert redirected_to(conn) == "/login?return=/sso/link"
    assert Repo.aggregate(Hexpm.Accounts.User, :count) == user_count
    assert Repo.get!(SSO.Transaction, pending["transaction_id"]).user_id == nil
  end

  test "a linked subject logs in directly and reports a changed provider email", context do
    previous_user = insert(:user)

    insert(:email,
      user: context.member,
      email: "renamed@identity.example.com",
      verified: false,
      primary: false,
      public: false,
      gravatar: false
    )

    insert(:organization_sso_identity,
      connection: context.connection,
      organization: context.organization,
      user: context.member,
      provider_email: List.first(context.member.emails).email
    )

    expect_authorization_request(context.connection)

    conn =
      build_conn()
      |> test_login(previous_user)
      |> put_session(
        "sudo_authenticated_at",
        NaiveDateTime.utc_now() |> NaiveDateTime.to_iso8601()
      )
      |> put_session("sudo_force", true)
      |> put_session("sudo_verification", true)
      |> put_session("sudo_return_to", "/dashboard/keys")
      |> get("/sso/#{context.organization.name}")

    assert_receive {:sso_state, state, redirect_uri}

    expect_code_exchange(
      context.connection,
      state,
      redirect_uri,
      "renamed@identity.example.com"
    )

    conn =
      conn
      |> recycle()
      |> get("/sso/callback", %{state: state, code: "authorization-code"})

    assert redirected_to(conn) == "/dashboard/orgs/#{context.organization.name}"
    assert get_session(conn, "session_token")
    refute get_session(conn, "sudo_authenticated_at")
    refute get_session(conn, "sudo_force")
    refute get_session(conn, "sudo_verification")
    refute get_session(conn, "sudo_return_to")
    assert_enqueued(worker: SSONotificationWorker)
    assert %Notification{kind: "email_mismatch"} = Repo.one!(Notification)

    identity = Repo.one!(Identity)
    assert identity.provider_email == "renamed@identity.example.com"
    refute List.first(context.member.emails).email == identity.provider_email

    login_log = Enum.find(AuditLogs.all_by(context.organization), &(&1.action == "sso.login"))
    assert login_log.user_id == context.member.id
    assert login_log.params["user_id"] == context.member.id
  end

  test "does not expose an organization login route when the feature is off", context do
    config = Application.fetch_env!(:hexpm, :organization_sso)
    Application.put_env(:hexpm, :organization_sso, Keyword.put(config, :mode, :off))

    build_conn()
    |> get("/sso/#{context.organization.name}")
    |> response(404)
  end

  test "rate limits public SSO starts before inserting a transaction", context do
    ip = {198, 51, 100, 42}
    time = System.system_time(:millisecond)

    for _attempt <- 1..30 do
      assert {:allow, _data} = Attack.sso_start_ip_throttle(ip, time: time)
    end

    before_count = Repo.aggregate(SSO.Transaction, :count)

    conn =
      build_conn()
      |> Map.put(:remote_ip, ip)
      |> get("/sso/#{context.organization.name}")

    assert response(conn, 429) =~ "Too many SSO login attempts"
    assert Repo.aggregate(SSO.Transaction, :count) == before_count
  end

  test "rate limits SSO starts per organization and IP without locking out other IPs", context do
    time = System.system_time(:millisecond)
    attacker_ip = {198, 51, 100, 44}
    legitimate_ip = {198, 51, 100, 45}

    for _attempt <- 1..20 do
      assert {:allow, _data} =
               Attack.sso_start_organization_throttle(context.organization.id, attacker_ip,
                 time: time
               )
    end

    before_count = Repo.aggregate(SSO.Transaction, :count)

    conn =
      build_conn()
      |> Map.put(:remote_ip, attacker_ip)
      |> get("/sso/#{context.organization.name}")

    assert response(conn, 429) =~ "Too many SSO login attempts"
    assert Repo.aggregate(SSO.Transaction, :count) == before_count

    expect_authorization_request(context.connection)

    conn =
      build_conn()
      |> Map.put(:remote_ip, legitimate_ip)
      |> get("/sso/#{context.organization.name}")

    assert redirected_to(conn) =~ "https://identity.example.com/authorize"
    assert Repo.aggregate(SSO.Transaction, :count) == before_count + 1
  end

  test "rate limits callbacks before state lookup or token exchange" do
    ip = {198, 51, 100, 43}
    time = System.system_time(:millisecond)

    for _attempt <- 1..50 do
      assert {:allow, _data} = Attack.sso_callback_ip_throttle(ip, time: time)
    end

    conn =
      build_conn()
      |> Map.put(:remote_ip, ip)
      |> get("/sso/callback", %{state: "unknown", code: "code"})

    assert response(conn, 429) =~ "Too many SSO callback attempts"
  end

  test "rejects unknown and replayed state", context do
    conn = get(build_conn(), "/sso/callback", %{state: "unknown", code: "code"})
    assert redirected_to(conn) == "/login"

    expect_authorization_request(context.connection)
    conn = get(build_conn(), "/sso/#{context.organization.name}")
    assert_receive {:sso_state, state, redirect_uri}
    expect_code_exchange(context.connection, state, redirect_uri, nil)

    conn =
      conn
      |> recycle()
      |> get("/sso/callback", %{state: state, code: "authorization-code"})

    assert redirected_to(conn) == "/login?return=/sso/link"

    replay = conn |> recycle() |> get("/sso/callback", %{state: state, code: "replayed"})
    assert redirected_to(replay) == "/login"
  end

  test "a failed code exchange preserves the browser-bound transaction", context do
    expect_authorization_request(context.connection)
    conn = get(build_conn(), "/sso/#{context.organization.name}")
    assert_receive {:sso_state, state, _redirect_uri}

    expect(OIDC.Mock, :exchange_code, fn _connection,
                                         _transaction,
                                         "bad-code",
                                         _redirect_uri,
                                         _secret ->
      {:error, %SSO.Error{stage: :token, code: :token_endpoint_rejected_request}}
    end)

    conn = conn |> recycle() |> get("/sso/callback", %{state: state, code: "bad-code"})
    assert redirected_to(conn) == "/login"
    assert SSO.get_transaction_by_state(state)
    assert state in get_session(conn, "sso_states")
  end

  defp enable_beta_for(organization) do
    config = Application.fetch_env!(:hexpm, :organization_sso)

    app_env(
      :hexpm,
      :organization_sso,
      Keyword.merge(config, mode: :beta, beta_organizations: [organization.name])
    )
  end

  defp expect_authorization_request(connection) do
    expect(OIDC.Mock, :authorization_uri, fn received_connection,
                                             transaction,
                                             redirect_uri,
                                             client_secret ->
      assert received_connection.id == connection.id
      assert client_secret == connection.client_secret
      assert transaction.redirect_uri == redirect_uri
      send(self(), {:sso_state, transaction.raw_state, redirect_uri})

      {:ok,
       "https://identity.example.com/authorize?state=#{URI.encode_www_form(transaction.raw_state)}"}
    end)
  end

  defp expect_code_exchange(connection, state, redirect_uri, email) do
    expect(OIDC.Mock, :exchange_code, fn received_connection,
                                         transaction,
                                         code,
                                         received_redirect_uri,
                                         client_secret ->
      assert received_connection.id == connection.id
      assert transaction.state_hash == :crypto.hash(:sha256, state)
      assert code == "authorization-code"
      assert received_redirect_uri == redirect_uri
      assert client_secret == connection.client_secret

      {:ok,
       %{
         issuer: connection.issuer,
         subject: "00u123",
         email: email,
         jwks_document: nil
       }}
    end)
  end

  defp begin_pending_link(context) do
    expect_authorization_request(context.connection)
    conn = get(build_conn(), "/sso/#{context.organization.name}")
    assert_receive {:sso_state, state, redirect_uri}
    expect_code_exchange(context.connection, state, redirect_uri, nil)

    conn
    |> recycle()
    |> get("/sso/callback", %{state: state, code: "authorization-code"})
  end

  defp assert_stale_link_is_cleared_after_password(conn, context) do
    %{"transaction_id" => transaction_id} = get_session(conn, "pending_sso_link")
    mock_pwned()

    conn =
      conn
      |> recycle()
      |> post("/login", %{
        username: context.member.username,
        password: "password",
        return: "/sso/link"
      })

    assert redirected_to(conn) == "/users/#{context.member.username}"
    assert get_session(conn, "session_token")
    refute get_session(conn, "pending_sso_link")
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "no longer valid"

    transaction = Repo.get!(SSO.Transaction, transaction_id)
    assert transaction.cancelled_at
    assert transaction.provider_email == nil

    assert [%{stage: "link", details: %{}}] = SSO.failures(context.connection)
  end
end
