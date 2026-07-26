defmodule HexpmWeb.SSOControllerTest do
  use HexpmWeb.ConnCase
  use Oban.Testing, repo: Hexpm.RepoBase

  import ExUnit.CaptureLog

  alias Hexpm.Accounts.{AuditLogs, SSO}
  alias Hexpm.Accounts.SSO.{Identity, OIDC}
  alias Hexpm.Emails.{OutboxEntry, OutboxEnvelope, OutboxWorker}
  alias HexpmWeb.Plugs.Attack

  setup :verify_on_exit!

  setup do
    PlugAttack.Storage.Ets.clean(HexpmWeb.Plugs.Attack.Storage)
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

  test "an empty beta allowlist hides every public SSO route", context do
    config = Application.fetch_env!(:hexpm, :organization_sso)

    app_env(
      :hexpm,
      :organization_sso,
      Keyword.merge(config, mode: :beta, beta_organizations: [])
    )

    build_conn()
    |> get("/sso/#{context.organization.name}")
    |> response(404)

    build_conn()
    |> get("/sso/callback", %{state: "unknown", code: "code"})
    |> response(404)

    build_conn()
    |> get("/sso/link")
    |> response(404)

    build_conn()
    |> post("/sso/link")
    |> response(404)

    build_conn()
    |> post("/sso/link/cancel")
    |> response(404)

    build_conn()
    |> get("/sso/confirm")
    |> response(404)

    build_conn()
    |> post("/sso/confirm")
    |> response(404)

    build_conn()
    |> get("/sso/discover")
    |> response(404)

    build_conn()
    |> post("/sso/discover")
    |> response(404)
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

  test "accepts organization-bound third-party initiation without persisting the login hint",
       context do
    login_hint = "Guest.User+oin@example.com"
    target_path = "/dashboard/orgs/#{context.organization.name}/packages?sort=name"
    target_link_uri = "http://localhost:5000" <> target_path
    expect_authorization_request(context.connection, login_hint: login_hint)

    query =
      URI.encode_query(%{
        "iss" => context.connection.issuer,
        "login_hint" => login_hint,
        "target_link_uri" => target_link_uri,
        "unknown_parameter" => "ignored"
      })

    conn = get(build_conn(), "/sso/#{context.organization.name}?#{query}")

    assert redirected_to(conn) =~ "https://identity.example.com/authorize"
    assert_no_store(conn)

    transaction = Repo.one!(SSO.Transaction)
    assert transaction.entrypoint == "third_party"
    assert transaction.return_path == target_path
    assert transaction.login_hint == nil
    assert transaction.provider_email == nil
  end

  test "ignores unknown third-party parameters as a conventional organization start", context do
    expect_authorization_request(context.connection)

    conn =
      get(
        build_conn(),
        "/sso/#{context.organization.name}?unknown=first&unknown=second&another=value"
      )

    assert redirected_to(conn) =~ "https://identity.example.com/authorize"
    assert Repo.one!(SSO.Transaction).entrypoint == "organization"
  end

  test "the canonical organization route cannot be shadowed by SSO control paths", context do
    organization = insert(:organization, name: "discover")
    enable_beta_for([context.organization, organization])

    connection =
      insert(:organization_sso_connection,
        organization: organization,
        tested_at: DateTime.utc_now(),
        enabled_at: DateTime.utc_now()
      )

    expect_authorization_request(connection)

    conn = get(build_conn(), "/sso/org/discover")
    assert redirected_to(conn) =~ "https://identity.example.com/authorize"

    html = build_conn() |> get("/sso/discover") |> html_response(200)
    assert html =~ "Enter your work email"
  end

  test "rejects duplicate recognized third-party parameters before transaction creation",
       context do
    issuer = URI.encode_www_form(context.connection.issuer)

    target =
      URI.encode_www_form("http://localhost:5000/dashboard/orgs/#{context.organization.name}")

    queries = [
      "iss=#{issuer}&iss=#{issuer}",
      "iss=#{issuer}&login_hint=one&login_hint=two",
      "iss=#{issuer}&target_link_uri=#{target}&target_link_uri=#{target}"
    ]

    for query <- queries do
      before_count = Repo.aggregate(SSO.Transaction, :count)
      conn = get(build_conn(), "/sso/#{context.organization.name}?#{query}")
      assert redirected_to(conn) == "/login"
      assert Repo.aggregate(SSO.Transaction, :count) == before_count
    end
  end

  test "requires the exact issuer and a bounded hint for recognized initiation parameters",
       context do
    invalid_queries = [
      URI.encode_query(%{"login_hint" => "person@example.com"}),
      URI.encode_query(%{"iss" => context.connection.issuer <> "/"}),
      URI.encode_query(%{
        "iss" => context.connection.issuer,
        "login_hint" => String.duplicate("a", 321)
      })
    ]

    for query <- invalid_queries do
      before_count = Repo.aggregate(SSO.Transaction, :count)
      conn = get(build_conn(), "/sso/#{context.organization.name}?#{query}")
      assert redirected_to(conn) == "/login"
      assert Repo.aggregate(SSO.Transaction, :count) == before_count
    end
  end

  test "rejects cross-origin and non-dashboard target link URIs", context do
    invalid_targets = [
      "https://evil.example/dashboard/orgs/#{context.organization.name}",
      "//evil.example/dashboard/orgs/#{context.organization.name}",
      "http://localhost:5000/dashboard/profile",
      "http://user@localhost:5000/dashboard/orgs/#{context.organization.name}",
      "http://localhost%2eevil.example:5000/dashboard/orgs/#{context.organization.name}",
      "http://localhost:5000%40evil.example/dashboard/orgs/#{context.organization.name}",
      "http://localhost:5000/dashboard/orgs/#{context.organization.name}#fragment",
      "http://localhost:5000/dashboard/orgs/#{context.organization.name}/../other",
      "http://localhost:5000/dashboard/orgs/#{context.organization.name}/%2e%2e/other",
      "http://localhost:5000/dashboard/orgs/#{context.organization.name}/%252e%252e/other"
    ]

    for target <- invalid_targets do
      query =
        URI.encode_query(%{
          "iss" => context.connection.issuer,
          "target_link_uri" => target
        })

      before_count = Repo.aggregate(SSO.Transaction, :count)
      conn = get(build_conn(), "/sso/#{context.organization.name}?#{query}")
      assert redirected_to(conn) == "/login"
      assert Repo.aggregate(SSO.Transaction, :count) == before_count
    end
  end

  test "accepted third-party initiations always create fresh state, nonce, and PKCE", context do
    expect(OIDC.Mock, :authorization_uri, 2, fn _connection,
                                                transaction,
                                                _redirect_uri,
                                                _client_secret ->
      send(
        self(),
        {:third_party_proof, transaction.raw_state, transaction.nonce, transaction.code_verifier}
      )

      {:ok,
       "https://identity.example.com/authorize?state=#{URI.encode_www_form(transaction.raw_state)}"}
    end)

    query = URI.encode_query(%{"iss" => context.connection.issuer})

    for _attempt <- 1..2 do
      conn = get(build_conn(), "/sso/#{context.organization.name}?#{query}")
      assert redirected_to(conn) =~ "https://identity.example.com/authorize"
    end

    assert_receive {:third_party_proof, first_state, first_nonce, first_verifier}
    assert_receive {:third_party_proof, second_state, second_nonce, second_verifier}
    refute first_state == second_state
    refute first_nonce == second_nonce
    refute first_verifier == second_verifier
  end

  test "does not log complete third-party initiation query strings", context do
    login_hint = "private-hint@example.com"
    target = "http://localhost:5000/dashboard/orgs/#{context.organization.name}"
    expect_authorization_request(context.connection, login_hint: login_hint)

    query =
      URI.encode_query(%{
        "iss" => context.connection.issuer,
        "login_hint" => login_hint,
        "target_link_uri" => target
      })

    log =
      capture_log([level: :debug], fn ->
        build_conn()
        |> get("/sso/#{context.organization.name}?#{query}")
        |> response(302)
      end)

    refute log =~ login_hint
    refute log =~ target
    refute log =~ query
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
    assert_no_store(conn)
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

    link_conn = conn |> recycle() |> get("/sso/link")
    assert_no_store(link_conn)
    html = html_response(link_conn, 200)
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
    assert_enqueued(worker: OutboxWorker)

    assert %OutboxEntry{
             category: "sso.identity_linked",
             scope_key: scope_key,
             expires_at: expires_at
           } = entry = Repo.one!(OutboxEntry)

    assert scope_key == "sso:user:#{context.member.id}"

    assert DateTime.diff(expires_at, DateTime.utc_now(), :second) in (30 * 24 * 60 * 60 - 60)..(30 *
                                                                                                  24 *
                                                                                                  60 *
                                                                                                  60)

    assert %{to: recipients, text_body: body} = OutboxEnvelope.load!(entry.email)
    assert recipients == Enum.map(context.member.emails, &{"", &1.email})
    assert body =~ context.organization.name
    assert body =~ context.member.username

    link_log =
      Enum.find(AuditLogs.all_by(context.organization), &(&1.action == "sso.identity.link"))

    assert link_log.user_id == context.member.id
    assert link_log.params["user_id"] == context.member.id
  end

  test "verified primary-email linking requires the mailed code and original browser",
       context do
    primary_email = List.first(context.member.emails)
    enable_automatic_linking(context.organization, primary_email.email)
    expect_authorization_request(context.connection)

    conn = get(build_conn(), "/sso/#{context.organization.name}")
    assert_no_store(conn)
    assert_receive {:sso_state, state, redirect_uri}
    expect_code_exchange(context.connection, state, redirect_uri, primary_email.email)

    conn =
      conn
      |> recycle()
      |> get("/sso/callback", %{state: state, code: "authorization-code"})

    assert redirected_to(conn) == "/sso/confirm"
    assert_no_store(conn)

    assert %{"transaction_id" => transaction_id, "capability" => capability} =
             get_session(conn, "pending_sso_confirmation")

    transaction = Repo.get!(SSO.Transaction, transaction_id)
    assert transaction.user_id == nil
    assert transaction.candidate_user_id == context.member.id
    assert transaction.candidate_email_id == primary_email.id
    assert transaction.link_method == "confirmed_primary_email"
    assert transaction.confirmation_attempts == 0
    assert transaction.confirmation_sends == 1
    assert is_binary(transaction.confirmation_code_hash)
    assert is_binary(transaction.browser_capability_hash)
    refute transaction.browser_capability_hash == capability

    {code, entry} = confirmation_code()
    assert %{to: [{"", recipient}], text_body: body} = OutboxEnvelope.load!(entry.email)
    assert recipient == primary_email.email
    assert body =~ context.organization.name
    assert body =~ code

    html = conn |> recycle() |> get("/sso/confirm") |> html_response(200)
    assert html =~ "Confirm organization SSO"
    refute html =~ primary_email.email

    code_only = post(build_conn(), "/sso/confirm", %{code: code})
    assert redirected_to(code_only) == "/login"
    refute Repo.exists?(Identity)

    session =
      get_session(conn)
      |> Map.put("tfa_user_id", %{
        "uid" => context.member.id,
        "at" => NaiveDateTime.utc_now() |> NaiveDateTime.to_iso8601(),
        "origin" => "conventional"
      })

    conn =
      conn
      |> recycle()
      |> Plug.Test.init_test_session(session)
      |> post("/sso/confirm", %{code: code})

    assert redirected_to(conn) == "/users/#{context.member.username}"
    refute get_session(conn, "pending_sso_confirmation")
    refute get_session(conn, "tfa_user_id")
    assert get_session(conn, "session_token")

    assert %Identity{
             user_id: user_id,
             organization_id: organization_id,
             link_method: "confirmed_primary_email"
           } = Repo.one!(Identity)

    assert user_id == context.member.id
    assert organization_id == context.organization.id

    transaction = Repo.get!(SSO.Transaction, transaction_id)
    assert transaction.linked_at
    assert transaction.candidate_user_id == nil
    assert transaction.candidate_email_id == nil
    assert transaction.domain_id == nil
    assert transaction.confirmation_code_hash == nil
    assert transaction.browser_capability_hash == nil
    assert transaction.issuer == nil
    assert transaction.subject == nil
    assert transaction.provider_email == nil

    refute Repo.exists?(
             from(entry in OutboxEntry, where: entry.category == "sso.confirmation_code")
           )

    assert Repo.exists?(
             from(entry in OutboxEntry, where: entry.category == "sso.identity_linked")
           )

    link_log =
      Enum.find(AuditLogs.all_by(context.organization), &(&1.action == "sso.identity.link"))

    assert link_log.params["link_method"] == "confirmed_primary_email"

    login_log = Enum.find(AuditLogs.all_by(context.organization), &(&1.action == "sso.login"))
    assert login_log.user_id == context.member.id
    assert login_log.params["entrypoint"] == "organization"
  end

  test "TFA-protected accounts finish confirmed primary-email linking only after TFA", context do
    member = insert(:user_with_tfa)
    insert(:organization_user, organization: context.organization, user: member, role: "read")
    confirmation = begin_confirmation(%{context | member: member})
    earlier_browser = confirmation.conn

    html = confirmation.conn |> recycle() |> get("/sso/confirm") |> html_response(200)
    assert html =~ "future organization SSO authentication"
    assert html =~ "without prompting for your personal Hexpm two-factor authentication code"
    assert html =~ "sudo-protected settings and actions"

    conn =
      confirmation.conn
      |> recycle()
      |> post("/sso/confirm", %{code: confirmation.code})

    assert redirected_to(conn) == "/tfa"
    assert get_session(conn, "tfa_user_id")["uid"] == member.id
    assert get_session(conn, "tfa_user_id")["origin"] == "sso_confirmation"

    assert get_session(conn, "pending_sso_confirmation")["transaction_id"] ==
             confirmation.transaction_id

    refute Repo.exists?(Identity)
    refute Repo.exists?(from(session in Hexpm.UserSession, where: session.user_id == ^member.id))

    transaction = Repo.get!(SSO.Transaction, confirmation.transaction_id)
    assert transaction.confirmation_verified_at

    assert DateTime.diff(
             transaction.confirmation_expires_at,
             transaction.confirmation_verified_at
           ) ==
             15 * 60

    expected_tfa_at =
      transaction.confirmation_verified_at
      |> DateTime.to_naive()
      |> NaiveDateTime.to_iso8601()

    assert get_session(conn, "tfa_user_id")["at"] == expected_tfa_at

    assert transaction.confirmation_code_hash == nil
    assert is_binary(transaction.browser_capability_hash)
    assert transaction.candidate_user_id == member.id

    conn = conn |> recycle() |> get("/sso/confirm")
    assert redirected_to(conn) == "/tfa"
    assert get_session(conn, "pending_sso_confirmation")
    assert get_session(conn, "tfa_user_id")["origin"] == "sso_confirmation"

    refute Repo.exists?(
             from(entry in OutboxEntry, where: entry.category == "sso.confirmation_code")
           )

    replayed =
      earlier_browser
      |> recycle()
      |> post("/sso/confirm", %{code: confirmation.code})

    assert redirected_to(replayed) == "/login"
    refute Repo.exists?(Identity)

    tfa_code = Hexpm.Accounts.TFA.time_based_token(member.tfa.secret)
    conn = conn |> recycle() |> post("/tfa", %{code: tfa_code})

    assert redirected_to(conn) == "/users/#{member.username}"
    assert get_session(conn, "session_token")
    refute get_session(conn, "pending_sso_confirmation")
    refute get_session(conn, "sudo_authenticated_at")

    assert %Identity{user_id: user_id, link_method: "confirmed_primary_email"} =
             Repo.one!(Identity)

    assert user_id == member.id

    transaction = Repo.get!(SSO.Transaction, confirmation.transaction_id)
    assert transaction.linked_at
    assert transaction.confirmation_verified_at == nil
    assert transaction.browser_capability_hash == nil
    assert transaction.candidate_user_id == nil

    back = conn |> recycle() |> get("/sso/confirm")
    assert redirected_to(back) == "/users/#{member.username}"
    refute Phoenix.Flash.get(back.assigns.flash, "error")
  end

  test "TFA recovery can finish confirmed primary-email linking", context do
    member = insert(:user_with_tfa)
    insert(:organization_user, organization: context.organization, user: member, role: "read")
    confirmation = begin_confirmation(%{context | member: member})

    conn =
      confirmation.conn
      |> recycle()
      |> post("/sso/confirm", %{code: confirmation.code})

    assert redirected_to(conn) == "/tfa"
    refute Repo.exists?(Identity)

    conn =
      conn
      |> recycle()
      |> post("/tfa/recovery", %{"code" => "1234-1234-1234-1234"})

    assert redirected_to(conn) == "/users/#{member.username}"
    assert get_session(conn, "session_token")
    refute get_session(conn, "pending_sso_confirmation")
    refute get_session(conn, "sudo_authenticated_at")
    assert %Identity{user_id: user_id} = Repo.one!(Identity)
    assert user_id == member.id
  end

  test "conventional TFA cancels a coexisting confirmation instead of proving it", context do
    member = insert(:user_with_tfa)
    insert(:organization_user, organization: context.organization, user: member, role: "read")
    confirmation = begin_confirmation(%{context | member: member})
    tfa_code = Hexpm.Accounts.TFA.time_based_token(member.tfa.secret)

    session =
      get_session(confirmation.conn)
      |> Map.put("tfa_user_id", %{
        "uid" => member.id,
        "at" => NaiveDateTime.utc_now() |> NaiveDateTime.to_iso8601(),
        "return" => nil,
        "origin" => "conventional"
      })

    conn =
      confirmation.conn
      |> recycle()
      |> Plug.Test.init_test_session(session)
      |> post("/tfa", %{code: tfa_code})

    assert redirected_to(conn) == "/users/#{member.username}"
    assert get_session(conn, "session_token")
    assert get_session(conn, "sudo_authenticated_at")
    refute get_session(conn, "pending_sso_confirmation")
    refute Repo.exists?(Identity)
    assert_confirmation_cleared(confirmation.transaction_id)
  end

  test "SSO-origin TFA without its browser-bound confirmation fails before login" do
    member = insert(:user_with_tfa)
    tfa_code = Hexpm.Accounts.TFA.time_based_token(member.tfa.secret)

    conn =
      build_conn()
      |> init_test_session(%{
        "tfa_user_id" => %{
          "uid" => member.id,
          "at" => NaiveDateTime.utc_now() |> NaiveDateTime.to_iso8601(),
          "return" => "/users/#{member.username}",
          "origin" => "sso_confirmation"
        }
      })
      |> post("/tfa", %{code: tfa_code})

    assert redirected_to(conn) == "/login"
    refute get_session(conn, "session_token")
    refute get_session(conn, "sudo_authenticated_at")

    assert Phoenix.Flash.get(conn.assigns.flash, "error") =~
             "Organization SSO could not be connected"

    refute Phoenix.Flash.get(conn.assigns.flash, "error") =~ "You are signed in"
  end

  test "verified confirmation fails closed when its TFA browser state does not match", context do
    member = insert(:user_with_tfa)
    insert(:organization_user, organization: context.organization, user: member, role: "read")
    confirmation = begin_confirmation(%{context | member: member})

    conn =
      confirmation.conn
      |> recycle()
      |> post("/sso/confirm", %{code: confirmation.code})

    assert redirected_to(conn) == "/tfa"

    session =
      get_session(conn)
      |> put_in(["tfa_user_id", "origin"], "conventional")

    conn =
      conn
      |> recycle()
      |> Plug.Test.init_test_session(session)
      |> get("/sso/confirm")

    assert redirected_to(conn) == "/login"
    refute get_session(conn, "pending_sso_confirmation")
    refute get_session(conn, "tfa_user_id")
    refute Repo.exists?(Identity)
    assert_confirmation_cleared(confirmation.transaction_id)
  end

  test "automatic-link fallbacks all use conventional account proof", context do
    enable_automatic_linking(context.organization, "example.com")

    secondary =
      insert(:email,
        user: context.member,
        email: "secondary@example.com",
        verified: true,
        primary: false,
        public: false,
        gravatar: false
      )

    unverified =
      insert(:email,
        user: context.member,
        email: "unverified@example.com",
        verified: false,
        primary: false,
        public: false,
        gravatar: false
      )

    outsider = insert(:user)
    outsider_email = List.first(outsider.emails)

    conflicted = insert(:user)
    conflicted_email = List.first(conflicted.emails)
    insert(:organization_user, organization: context.organization, user: conflicted)

    insert(:organization_sso_identity,
      connection: context.connection,
      organization: context.organization,
      user: conflicted,
      subject: "different-subject"
    )

    for provider_email <- [
          nil,
          "not-an-email",
          secondary.email,
          unverified.email,
          outsider_email.email,
          conflicted_email.email
        ] do
      expect_authorization_request(context.connection)
      conn = get(build_conn(), "/sso/#{context.organization.name}")
      assert_receive {:sso_state, state, redirect_uri}
      expect_code_exchange(context.connection, state, redirect_uri, provider_email)

      conn =
        conn
        |> recycle()
        |> get("/sso/callback", %{state: state, code: "authorization-code"})

      assert redirected_to(conn) == "/login?return=/sso/link"

      assert %{"transaction_id" => transaction_id, "token" => _token} =
               get_session(conn, "pending_sso_link")

      transaction = Repo.get!(SSO.Transaction, transaction_id)
      assert transaction.user_id == nil
      assert transaction.candidate_user_id == nil
      assert transaction.link_method == "conventional"
    end
  end

  test "confirmation attempts are browser-bound and clear all proof after five failures",
       context do
    %{conn: conn, transaction_id: transaction_id, capability: capability, code: code} =
      begin_confirmation(context)

    assert SSO.confirm_link_code(
             transaction_id,
             "different-browser-capability",
             code,
             nil,
             audit_data(context.member)
           ) == {:error, :invalid_confirmation}

    assert Repo.get!(SSO.Transaction, transaction_id).confirmation_attempts == 0

    conn =
      Enum.reduce(1..4, conn, fn _attempt, conn ->
        conn = conn |> recycle() |> post("/sso/confirm", %{code: "AAAAAAAAAA"})
        assert html_response(conn, 200) =~ "confirmation code was not valid"
        conn
      end)

    assert Repo.get!(SSO.Transaction, transaction_id).confirmation_attempts == 4

    conn = conn |> recycle() |> post("/sso/confirm", %{code: "AAAAAAAAAA"})
    assert redirected_to(conn) == "/login"

    transaction = Repo.get!(SSO.Transaction, transaction_id)
    assert transaction.cancelled_at
    assert transaction.candidate_user_id == nil
    assert transaction.confirmation_code_hash == nil
    assert transaction.browser_capability_hash == nil
    refute Repo.exists?(Identity)

    refute Repo.exists?(
             from(entry in OutboxEntry, where: entry.category == "sso.confirmation_code")
           )

    assert SSO.confirm_link_code(
             transaction_id,
             capability,
             code,
             nil,
             audit_data(context.member)
           ) == {:error, :confirmation_cancelled}
  end

  test "resends rotate the code, cap total sends at three, and reject replay", context do
    %{conn: conn, transaction_id: transaction_id, code: first_code} =
      begin_confirmation(context)

    conn = conn |> recycle() |> post("/sso/confirm/resend")
    assert redirected_to(conn) == "/sso/confirm"
    {second_code, _entry} = confirmation_code()
    refute second_code == first_code
    assert Repo.get!(SSO.Transaction, transaction_id).confirmation_sends == 2

    conn = conn |> recycle() |> post("/sso/confirm", %{code: first_code})
    assert html_response(conn, 200) =~ "confirmation code was not valid"

    conn = conn |> recycle() |> post("/sso/confirm/resend")
    assert redirected_to(conn) == "/sso/confirm"
    {third_code, _entry} = confirmation_code()
    refute third_code in [first_code, second_code]

    transaction = Repo.get!(SSO.Transaction, transaction_id)
    assert transaction.confirmation_sends == 3
    assert transaction.confirmation_attempts == 1

    conn = conn |> recycle() |> post("/sso/confirm/resend")
    assert html_response(conn, 200) =~ "maximum number of confirmation codes"
    assert get_session(conn, "pending_sso_confirmation")

    conn = conn |> recycle() |> post("/sso/confirm", %{code: third_code})
    assert redirected_to(conn) == "/users/#{context.member.username}"

    assert SSO.confirm_link_code(
             transaction_id,
             get_in(get_session(conn, "pending_sso_confirmation"), ["capability"]),
             third_code,
             nil,
             audit_data(context.member)
           ) == {:error, :confirmation_already_used}

    assert Repo.aggregate(Identity, :count) == 1
  end

  test "expired confirmation proof and queued mail are cleared by the bounded worker", context do
    %{transaction_id: transaction_id, capability: capability} = begin_confirmation(context)

    Repo.update_all(
      from(transaction in SSO.Transaction, where: transaction.id == ^transaction_id),
      set: [confirmation_expires_at: DateTime.add(DateTime.utc_now(), -1, :second)]
    )

    assert Hexpm.Accounts.SSO.ConfirmationPruner.perform(%Oban.Job{args: %{}}) == :ok

    transaction = Repo.get!(SSO.Transaction, transaction_id)
    assert transaction.cancelled_at
    assert transaction.candidate_user_id == nil
    assert transaction.confirmation_code_hash == nil
    assert transaction.browser_capability_hash == nil
    assert SSO.get_pending_confirmation(transaction_id, capability) == nil

    refute Repo.exists?(
             from(entry in OutboxEntry, where: entry.category == "sso.confirmation_code")
           )

    assert Hexpm.Accounts.SSO.ConfirmationPruner.perform(%Oban.Job{
             args: %{"unexpected" => true}
           }) ==
             {:cancel, {:invalid_args, %{"unexpected" => true}}}
  end

  test "a new confirmation replaces pending proof for the same provider subject", context do
    first = begin_confirmation(context)
    second = begin_confirmation(context)

    first_transaction = Repo.get!(SSO.Transaction, first.transaction_id)
    assert first_transaction.cancelled_at
    assert first_transaction.candidate_user_id == nil
    assert first_transaction.confirmation_code_hash == nil
    assert first_transaction.browser_capability_hash == nil

    assert SSO.get_pending_confirmation(first.transaction_id, first.capability) == nil
    assert SSO.get_pending_confirmation(second.transaction_id, second.capability)

    assert Repo.aggregate(
             from(entry in OutboxEntry, where: entry.category == "sso.confirmation_code"),
             :count
           ) == 1
  end

  test "disabling a connection proactively cancels confirmation proof and queued mail", context do
    confirmation = begin_confirmation(context)

    assert {:ok, disabled} =
             SSO.disable(context.organization, audit: audit_data(context.member))

    refute SSO.Connection.enabled?(disabled)
    assert_confirmation_cleared(confirmation.transaction_id)

    assert SSO.get_pending_confirmation(confirmation.transaction_id, confirmation.capability) ==
             nil
  end

  test "confirmation revalidates primary email, membership, domain, and connection versions",
       context do
    for mutation <- [:primary_email, :membership, :domain, :connection] do
      confirmation = begin_confirmation(context)
      transaction = Repo.get!(SSO.Transaction, confirmation.transaction_id)

      case mutation do
        :primary_email ->
          Repo.update_all(
            from(email in Hexpm.Accounts.Email,
              where: email.id == ^transaction.candidate_email_id
            ),
            set: [primary: false]
          )

        :membership ->
          Repo.delete_all(
            from(member in Hexpm.Accounts.OrganizationUser,
              where: member.organization_id == ^context.organization.id,
              where: member.user_id == ^context.member.id
            )
          )

        :domain ->
          Repo.update_all(
            from(domain in SSO.Domain, where: domain.id == ^transaction.domain_id),
            set: [state: "invalid", valid_until: nil, invalidated_at: DateTime.utc_now()]
          )

        :connection ->
          Repo.update_all(
            from(connection in SSO.Connection, where: connection.id == ^context.connection.id),
            inc: [version: 1]
          )
      end

      assert SSO.get_pending_confirmation(confirmation.transaction_id, confirmation.capability) ==
               nil

      assert_confirmation_cleared(confirmation.transaction_id)

      conn =
        confirmation.conn
        |> recycle()
        |> post("/sso/confirm", %{code: confirmation.code})

      assert redirected_to(conn) == "/login"
      refute Repo.exists?(Identity)

      cleared = Repo.get!(SSO.Transaction, confirmation.transaction_id)
      assert cleared.cancelled_at
      assert cleared.candidate_user_id == nil
      assert cleared.confirmation_code_hash == nil

      restore_confirmation_fixture(context, mutation, transaction)
    end
  end

  test "a different active session forces conventional proof for an otherwise eligible account",
       context do
    previous_user = insert(:user)
    primary_email = List.first(context.member.emails)
    enable_automatic_linking(context.organization, primary_email.email)
    expect_authorization_request(context.connection)

    conn =
      build_conn()
      |> test_login(previous_user)
      |> get("/sso/#{context.organization.name}")

    assert_receive {:sso_state, state, redirect_uri}
    expect_code_exchange(context.connection, state, redirect_uri, primary_email.email)

    conn =
      conn
      |> recycle()
      |> get("/sso/callback", %{state: state, code: "authorization-code"})

    assert redirected_to(conn) == "/login?return=/sso/link"
    assert get_session(conn, "session_token")
    assert get_session(conn, "pending_sso_link")
    refute get_session(conn, "pending_sso_confirmation")
    refute Repo.exists?(Identity)
  end

  test "confirmation rejects a different active Hexpm session", context do
    confirmation = begin_confirmation(context)
    previous_user = insert(:user)

    conn =
      build_conn()
      |> test_login(previous_user)
      |> put_session(
        "pending_sso_confirmation",
        get_session(confirmation.conn, "pending_sso_confirmation")
      )
      |> post("/sso/confirm", %{code: confirmation.code})

    assert redirected_to(conn) == "/login"
    assert get_session(conn, "session_token")
    refute get_session(conn, "pending_sso_confirmation")
    assert conn.assigns.current_user.id == previous_user.id
    refute Repo.exists?(Identity)
    assert_confirmation_cleared(confirmation.transaction_id)
  end

  test "cross-transaction subject throttling falls back without sending a code", context do
    primary_email = List.first(context.member.emails)
    enable_automatic_linking(context.organization, primary_email.email)
    expect_authorization_request(context.connection)

    conn = get(build_conn(), "/sso/#{context.organization.name}")
    assert_receive {:sso_state, state, redirect_uri}
    expect_code_exchange(context.connection, state, redirect_uri, primary_email.email)

    time = System.system_time(:millisecond)
    subject_hash = SSO.throttle_hash("00u123")

    for _attempt <- 1..10 do
      assert {:allow, _data} = Attack.sso_link_subject_throttle(subject_hash, time: time)
    end

    conn =
      conn
      |> recycle()
      |> get("/sso/callback", %{state: state, code: "authorization-code"})

    assert redirected_to(conn) == "/login?return=/sso/link"
    assert get_session(conn, "pending_sso_link")
    refute get_session(conn, "pending_sso_confirmation")

    refute Repo.exists?(
             from(entry in OutboxEntry, where: entry.category == "sso.confirmation_code")
           )
  end

  test "cancelling confirmation clears candidate proof and queued mail", context do
    confirmation = begin_confirmation(context)

    conn = confirmation.conn |> recycle() |> post("/sso/confirm/cancel")
    assert redirected_to(conn) == "/login"
    refute get_session(conn, "pending_sso_confirmation")

    transaction = Repo.get!(SSO.Transaction, confirmation.transaction_id)
    assert transaction.cancelled_at
    assert transaction.candidate_user_id == nil
    assert transaction.candidate_email_id == nil
    assert transaction.confirmation_code_hash == nil
    assert transaction.browser_capability_hash == nil
    refute Repo.exists?(Identity)

    refute Repo.exists?(
             from(entry in OutboxEntry, where: entry.category == "sso.confirmation_code")
           )
  end

  test "logout revokes pending confirmation before an earlier browser session can be replayed",
       context do
    confirmation = begin_confirmation(context)
    earlier_browser = confirmation.conn

    conn = earlier_browser |> recycle() |> post("/logout")

    assert redirected_to(conn) == "/"
    refute get_session(conn, "pending_sso_confirmation")
    assert_confirmation_cleared(confirmation.transaction_id)

    replayed =
      earlier_browser
      |> recycle()
      |> post("/sso/confirm", %{code: confirmation.code})

    assert redirected_to(replayed) == "/login"
    refute Repo.exists?(Identity)
  end

  test "logout revokes a pending linked login before browser-session replay", context do
    pending = begin_pending_login(context)
    earlier_browser = pending.conn

    conn = earlier_browser |> recycle() |> post("/logout")

    assert redirected_to(conn) == "/"
    refute get_session(conn, "pending_sso_login")

    transaction = Repo.get!(SSO.Transaction, pending.transaction_id)
    assert transaction.cancelled_at
    assert transaction.user_id == nil
    assert transaction.link_token_hash == nil

    replayed = earlier_browser |> recycle() |> post("/sso/continue")
    assert redirected_to(replayed) == "/login"
    refute get_session(replayed, "session_token")
  end

  test "a password session replacement revokes a pending linked login", context do
    pending = begin_pending_login(context)
    earlier_browser = pending.conn
    mock_pwned()

    conn =
      earlier_browser
      |> recycle()
      |> post("/login", %{
        username: context.member.username,
        password: "password"
      })

    assert redirected_to(conn) == "/users/#{context.member.username}"
    assert get_session(conn, "session_token")
    refute get_session(conn, "pending_sso_login")

    transaction = Repo.get!(SSO.Transaction, pending.transaction_id)
    assert transaction.cancelled_at
    assert transaction.user_id == nil
    assert transaction.link_token_hash == nil

    replayed = earlier_browser |> recycle() |> post("/sso/continue")
    assert redirected_to(replayed) == "/login"
  end

  test "password plus TFA revokes a pending linked login before the TFA session is created",
       context do
    member = insert(:user_with_tfa)
    insert(:organization_user, organization: context.organization, user: member, role: "admin")
    context = %{context | member: member}
    pending = begin_pending_login(context)
    earlier_browser = pending.conn
    mock_pwned()

    conn =
      pending.conn
      |> recycle()
      |> post("/login", %{username: member.username, password: "password"})

    assert redirected_to(conn) == "/tfa"
    refute get_session(conn, "pending_sso_login")

    transaction = Repo.get!(SSO.Transaction, pending.transaction_id)
    assert transaction.cancelled_at
    assert transaction.user_id == nil
    assert transaction.link_token_hash == nil

    token = Hexpm.Accounts.TFA.time_based_token(member.tfa.secret)
    conn = conn |> recycle() |> post("/tfa", %{code: token})
    assert redirected_to(conn) == "/users/#{member.username}"
    assert get_session(conn, "session_token")

    replayed = earlier_browser |> recycle() |> post("/sso/continue")
    assert redirected_to(replayed) == "/login"
    refute get_session(replayed, "session_token")
  end

  test "GitHub plus TFA revokes pending confirmation proof and queued mail", context do
    member = insert(:user_with_tfa)
    insert(:organization_user, organization: context.organization, user: member, role: "admin")
    insert(:user_provider, user: member, provider: "github", provider_uid: "sso-tfa-github")
    confirmation = begin_confirmation(%{context | member: member})
    earlier_browser = confirmation.conn
    session_snapshot = get_session(confirmation.conn)

    conn =
      confirmation.conn
      |> recycle()
      |> mock_github_auth_success(
        "sso-tfa-github",
        List.first(member.emails).email
      )
      |> Plug.Test.init_test_session(session_snapshot)
      |> HexpmWeb.AuthController.callback(%{})

    assert redirected_to(conn) == "/tfa"
    refute get_session(conn, "pending_sso_confirmation")
    assert_confirmation_cleared(confirmation.transaction_id)

    assert %{"uid" => member_id} = tfa_session = get_session(conn, "tfa_user_id")
    assert member_id == member.id
    refute Map.has_key?(tfa_session, "session_token")

    refute Repo.exists?(
             from(session in Hexpm.UserSession,
               where: session.user_id == ^member.id,
               where: session.type == "browser"
             )
           )

    replayed =
      earlier_browser
      |> recycle()
      |> post("/sso/confirm", %{code: confirmation.code})

    assert redirected_to(replayed) == "/login"
    refute Repo.exists?(Identity)
  end

  test "a replacement SSO flow revokes the previous browser capability and queued code",
       context do
    confirmation = begin_confirmation(context)
    earlier_browser = confirmation.conn
    expect_authorization_request(context.connection)

    conn =
      earlier_browser
      |> recycle()
      |> get("/sso/#{context.organization.name}")

    assert_receive {:sso_state, state, redirect_uri}
    expect_code_exchange(context.connection, state, redirect_uri, nil)

    conn =
      conn
      |> recycle()
      |> get("/sso/callback", %{state: state, code: "authorization-code"})

    assert redirected_to(conn) == "/login?return=/sso/link"
    assert get_session(conn, "pending_sso_link")
    refute get_session(conn, "pending_sso_confirmation")
    assert_confirmation_cleared(confirmation.transaction_id)

    replayed =
      earlier_browser
      |> recycle()
      |> post("/sso/confirm", %{code: confirmation.code})

    assert redirected_to(replayed) == "/login"
    refute Repo.exists?(Identity)
  end

  test "a forged browser capability cannot cancel a valid confirmation during logout", context do
    confirmation = begin_confirmation(context)

    conn =
      build_conn()
      |> init_test_session(%{
        "pending_sso_confirmation" => %{
          "transaction_id" => confirmation.transaction_id,
          "capability" => "forged-browser-capability"
        }
      })
      |> post("/logout")

    assert redirected_to(conn) == "/"

    transaction = Repo.get!(SSO.Transaction, confirmation.transaction_id)
    refute transaction.cancelled_at
    assert transaction.candidate_user_id == context.member.id
    assert is_binary(transaction.confirmation_code_hash)
    assert is_binary(transaction.browser_capability_hash)
    ordering_key = "sso-confirmation:#{confirmation.transaction_id}"

    assert Repo.exists?(
             from(entry in OutboxEntry,
               where: entry.ordering_key == ^ordering_key,
               where: entry.category == "sso.confirmation_code"
             )
           )
  end

  test "confirmation fails closed when its organization leaves the feature gate", context do
    confirmation = begin_confirmation(context)
    other = insert(:organization)
    enable_beta_for(other)

    conn = confirmation.conn |> recycle() |> get("/sso/confirm")
    assert redirected_to(conn) == "/login"
    refute get_session(conn, "pending_sso_confirmation")

    transaction = Repo.get!(SSO.Transaction, confirmation.transaction_id)
    assert transaction.cancelled_at
    assert transaction.candidate_user_id == nil
    assert transaction.confirmation_code_hash == nil

    refute Repo.exists?(
             from(entry in OutboxEntry, where: entry.category == "sso.confirmation_code")
           )
  end

  test "confirmed identities remain isolated across organizations sharing a domain", context do
    other = insert(:organization)
    insert(:organization_user, organization: other, user: context.member)
    enable_beta_for([context.organization, other])

    other_connection =
      insert(:organization_sso_connection,
        organization: other,
        tested_at: DateTime.utc_now(),
        enabled_at: DateTime.utc_now()
      )

    first = begin_confirmation(context)

    assert first.conn
           |> recycle()
           |> post("/sso/confirm", %{code: first.code})
           |> redirected_to() == "/users/#{context.member.username}"

    second =
      begin_confirmation(%{
        context
        | organization: other,
          connection: other_connection
      })

    assert second.conn
           |> recycle()
           |> post("/sso/confirm", %{code: second.code})
           |> redirected_to() == "/users/#{context.member.username}"

    assert Enum.sort(Repo.all(from(identity in Identity, select: identity.organization_id))) ==
             Enum.sort([context.organization.id, other.id])
  end

  test "an anonymous linked callback requires a browser-confirmed POST before login", context do
    identity =
      insert(:organization_sso_identity,
        connection: context.connection,
        organization: context.organization,
        user: context.member
      )

    expect_authorization_request(context.connection)
    conn = get(build_conn(), "/sso/#{context.organization.name}")
    assert_receive {:sso_state, state, redirect_uri}
    expect_code_exchange(context.connection, state, redirect_uri, identity.provider_email)

    conn =
      conn
      |> recycle()
      |> get("/sso/callback", %{state: state, code: "authorization-code"})

    assert redirected_to(conn) == "/sso/continue"
    assert_no_store(conn)
    refute get_session(conn, "session_token")

    assert %{"transaction_id" => transaction_id, "capability" => capability} =
             get_session(conn, "pending_sso_login")

    transaction = Repo.get!(SSO.Transaction, transaction_id)
    assert transaction.user_id == context.member.id
    assert transaction.issuer == identity.issuer
    assert transaction.subject == identity.subject
    assert is_binary(transaction.link_token_hash)
    refute transaction.link_token_hash == capability
    refute Enum.any?(AuditLogs.all_by(context.organization), &(&1.action == "sso.login"))

    continue_conn = conn |> recycle() |> get("/sso/continue")
    assert_no_store(continue_conn)
    html = html_response(continue_conn, 200)
    assert html =~ "Continue with organization SSO"
    assert html =~ context.organization.name

    conn = continue_conn |> recycle() |> post("/sso/continue")

    assert redirected_to(conn) == "/users/#{context.member.username}"
    assert_no_store(conn)
    assert get_session(conn, "session_token")
    refute get_session(conn, "pending_sso_login")

    login_log = Enum.find(AuditLogs.all_by(context.organization), &(&1.action == "sso.login"))
    assert login_log.user_id == context.member.id

    transaction = Repo.get!(SSO.Transaction, transaction_id)
    assert transaction.user_id == nil
    assert transaction.issuer == nil
    assert transaction.subject == nil
    assert transaction.provider_email == nil
    assert transaction.link_token_hash == nil

    back = conn |> recycle() |> get("/sso/continue")
    assert redirected_to(back) == "/users/#{context.member.username}"
    refute Phoenix.Flash.get(back.assigns.flash, "error")
  end

  test "a linked subject matching the active Hexpm session completes immediately", context do
    identity =
      insert(:organization_sso_identity,
        connection: context.connection,
        organization: context.organization,
        user: context.member
      )

    expect_authorization_request(context.connection)

    conn =
      build_conn()
      |> test_login(context.member)
      |> get("/sso/#{context.organization.name}")

    assert_receive {:sso_state, state, redirect_uri}
    expect_code_exchange(context.connection, state, redirect_uri, identity.provider_email)

    conn =
      conn
      |> recycle()
      |> get("/sso/callback", %{state: state, code: "authorization-code"})

    assert redirected_to(conn) == "/users/#{context.member.username}"
    assert get_session(conn, "session_token")
    refute get_session(conn, "pending_sso_login")
    assert Enum.any?(AuditLogs.all_by(context.organization), &(&1.action == "sso.login"))
  end

  test "cancelling or replaying a pending linked login never starts a session", context do
    pending = begin_pending_login(context)
    earlier_browser = pending.conn

    conn = earlier_browser |> recycle() |> post("/sso/continue/cancel")
    assert redirected_to(conn) == "/login"
    assert_no_store(conn)
    refute get_session(conn, "session_token")
    refute get_session(conn, "pending_sso_login")

    transaction = Repo.get!(SSO.Transaction, pending.transaction_id)
    assert transaction.cancelled_at
    assert transaction.user_id == nil
    assert transaction.issuer == nil
    assert transaction.subject == nil
    assert transaction.provider_email == nil
    assert transaction.link_token_hash == nil

    replayed = earlier_browser |> recycle() |> post("/sso/continue")
    assert redirected_to(replayed) == "/login"
    refute get_session(replayed, "session_token")
    refute Enum.any?(AuditLogs.all_by(context.organization), &(&1.action == "sso.login"))
  end

  test "pending linked login never replaces a different active Hexpm session", context do
    pending = begin_pending_login(context)
    previous_user = insert(:user)

    conn =
      build_conn()
      |> test_login(previous_user)
      |> put_session("pending_sso_login", get_session(pending.conn, "pending_sso_login"))
      |> post("/sso/continue")

    assert redirected_to(conn) == "/login"
    assert get_session(conn, "session_token")
    refute get_session(conn, "pending_sso_login")
    assert conn.assigns.current_user.id == previous_user.id
    refute Enum.any?(AuditLogs.all_by(context.organization), &(&1.action == "sso.login"))

    transaction = Repo.get!(SSO.Transaction, pending.transaction_id)
    assert transaction.cancelled_at
    assert transaction.link_token_hash == nil
  end

  test "linked callbacks do not consume first-link subject throttles", context do
    pending = begin_pending_login(context)
    time = System.system_time(:millisecond)
    subject_hash = SSO.throttle_hash("00u123")

    for _attempt <- 1..10 do
      assert {:allow, _data} = Attack.sso_link_subject_throttle(subject_hash, time: time)
    end

    conn = pending.conn |> recycle() |> post("/sso/continue/cancel")
    assert redirected_to(conn) == "/login"
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

  test "a feature disabled before password proof clears the stale link without exposing SSO",
       context do
    conn = begin_pending_link(context)
    %{"transaction_id" => transaction_id} = get_session(conn, "pending_sso_link")
    config = Application.fetch_env!(:hexpm, :organization_sso)
    Application.put_env(:hexpm, :organization_sso, Keyword.put(config, :mode, :off))
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
    refute Phoenix.Flash.get(conn.assigns.flash, :error)

    transaction = Repo.get!(SSO.Transaction, transaction_id)
    assert transaction.cancelled_at
    assert transaction.provider_email == nil
    assert SSO.failures(context.connection) == []
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

  test "a linked subject never replaces a different active Hexpm session", context do
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

    assert redirected_to(conn) == "/login"
    assert get_session(conn, "session_token")
    assert get_session(conn, "sudo_authenticated_at")
    assert get_session(conn, "sudo_force")
    assert get_session(conn, "sudo_verification")
    assert get_session(conn, "sudo_return_to")
    refute_enqueued(worker: OutboxWorker)

    identity = Repo.one!(Identity)
    assert identity.provider_email == List.first(context.member.emails).email
    refute Enum.any?(AuditLogs.all_by(context.organization), &(&1.action == "sso.login"))
  end

  test "does not expose an organization login route when the feature is off", context do
    config = Application.fetch_env!(:hexpm, :organization_sso)
    Application.put_env(:hexpm, :organization_sso, Keyword.put(config, :mode, :off))

    build_conn()
    |> get("/sso/#{context.organization.name}")
    |> response(404)

    build_conn()
    |> get("/sso/discover")
    |> response(404)
  end

  test "discovery returns generic no-store guidance without an eligible organization" do
    conn = post(build_conn(), "/sso/discover", %{email: "private.person@missing.example.com"})

    assert html_response(conn, 200) =~ "could not find an organization SSO sign-in"
    assert get_resp_header(conn, "cache-control") == ["no-store"]
    refute response(conn, 200) =~ "private.person"
    assert Repo.aggregate(SSO.Transaction, :count) == 0
  end

  test "discovery starts a fresh organization-bound transaction for one exact domain", context do
    enable_discovery(context.organization, "example.com")
    expect_authorization_request(context.connection)

    conn = post(build_conn(), "/sso/discover", %{email: "Person@EXAMPLE.com."})

    # Handed off to the organization route so the provider redirect is a plain
    # navigation rather than the continuation of a form submission.
    assert html_response(conn, 200) =~ "/sso/org/#{context.organization.name}"
    assert get_resp_header(conn, "cache-control") == ["no-store"]
    assert Repo.aggregate(SSO.Transaction, :count) == 0

    conn = conn |> recycle() |> get("/sso/org/#{context.organization.name}")

    assert redirected_to(conn) =~ "https://identity.example.com/authorize"

    transaction = Repo.one!(SSO.Transaction)
    assert transaction.connection_id == context.connection.id
    assert transaction.entrypoint == "discovery"
    assert transaction.user_id == nil
    assert transaction.provider_email == nil
  end

  test "a discovery hand-off revalidates before granting the discovery entrypoint", context do
    domain = enable_discovery(context.organization, "example.com")

    conn = post(build_conn(), "/sso/discover", %{email: "person@example.com"})
    assert html_response(conn, 200) =~ "/sso/org/#{context.organization.name}"

    domain
    |> Ecto.Changeset.change(discovery_enabled: false)
    |> Repo.update!()

    expect_authorization_request(context.connection)
    conn = conn |> recycle() |> get("/sso/org/#{context.organization.name}")

    assert redirected_to(conn) =~ "https://identity.example.com/authorize"

    transaction = Repo.one!(SSO.Transaction)
    assert transaction.entrypoint == "organization"
    assert transaction.domain_id == nil
  end

  test "shared domains present only eligible organization choices and recheck the choice",
       context do
    other = insert(:organization)
    enable_beta_for([context.organization, other])

    other_connection =
      insert(:organization_sso_connection,
        organization: other,
        tested_at: DateTime.utc_now(),
        enabled_at: DateTime.utc_now()
      )

    first = enable_discovery(context.organization, "shared.example.com")
    enable_discovery(other, first.domain)

    conn =
      post(build_conn(), "/sso/discover", %{email: "private.person@SHARED.example.com"})

    html = html_response(conn, 200)
    assert html =~ context.organization.name
    assert html =~ other.name
    assert html =~ ~s(value="shared.example.com")
    refute html =~ "private.person"
    assert get_resp_header(conn, "cache-control") == ["no-store"]
    assert Repo.aggregate(SSO.Transaction, :count) == 0

    expect_authorization_request(other_connection)

    selected =
      post(conn, "/sso/discover/choose", %{
        domain: "shared.example.com",
        organization: other.name
      })

    assert html_response(selected, 200) =~ "/sso/org/#{other.name}"

    selected = selected |> recycle() |> get("/sso/org/#{other.name}")

    assert redirected_to(selected) =~ "https://identity.example.com/authorize"
    assert Repo.one!(SSO.Transaction).connection_id == other_connection.id

    Repo.update_all(
      from(domain in SSO.Domain, where: domain.id == ^first.id),
      set: [discovery_enabled: false]
    )

    before_count = Repo.aggregate(SSO.Transaction, :count)

    stale =
      post(build_conn(), "/sso/discover/choose", %{
        domain: "shared.example.com",
        organization: context.organization.name
      })

    assert html_response(stale, 200) =~ "could not find an organization SSO sign-in"
    assert Repo.aggregate(SSO.Transaction, :count) == before_count
  end

  test "rate limits discovery before creating a transaction", context do
    enable_discovery(context.organization, "example.com")
    ip = {198, 51, 100, 46}
    time = System.system_time(:millisecond)

    for _attempt <- 1..20 do
      assert {:allow, _data} = Attack.sso_discovery_ip_throttle(ip, time: time)
    end

    conn =
      build_conn()
      |> Map.put(:remote_ip, ip)
      |> post("/sso/discover", %{email: "person@example.com"})

    assert response(conn, 429) =~ "Too many SSO discovery attempts"
    assert Repo.aggregate(SSO.Transaction, :count) == 0
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

  defp enable_beta_for(organizations) do
    config = Application.fetch_env!(:hexpm, :organization_sso)
    organizations = List.wrap(organizations)

    app_env(
      :hexpm,
      :organization_sso,
      Keyword.merge(config,
        mode: :beta,
        beta_organizations: Enum.map(organizations, & &1.name)
      )
    )
  end

  defp enable_discovery(organization, domain) do
    insert(:organization_sso_domain,
      organization: organization,
      domain: domain,
      state: "verified",
      verified_at: DateTime.utc_now(),
      last_checked_at: DateTime.utc_now(),
      valid_until: DateTime.add(DateTime.utc_now(), 6 * 24 * 60 * 60, :second),
      discovery_enabled: true
    )
  end

  defp enable_automatic_linking(organization, value) do
    {:ok, domain} =
      case SSO.discovery_domain(value) do
        {:ok, domain} -> {:ok, domain}
        {:error, _reason} -> SSO.canonical_domain(value)
      end

    case Repo.get_by(SSO.Domain, organization_id: organization.id, domain: domain) do
      nil ->
        insert(:organization_sso_domain,
          organization: organization,
          domain: domain,
          state: "verified",
          verified_at: DateTime.utc_now(),
          last_checked_at: DateTime.utc_now(),
          valid_until: DateTime.add(DateTime.utc_now(), 6 * 24 * 60 * 60, :second),
          automatic_linking_enabled: true
        )

      existing ->
        existing
        |> Ecto.Changeset.change(
          state: "verified",
          verified_at: DateTime.utc_now(),
          last_checked_at: DateTime.utc_now(),
          valid_until: DateTime.add(DateTime.utc_now(), 6 * 24 * 60 * 60, :second),
          invalidated_at: nil,
          automatic_linking_enabled: true
        )
        |> Repo.update!()
    end
  end

  defp begin_confirmation(context) do
    primary_email = List.first(context.member.emails)
    enable_automatic_linking(context.organization, primary_email.email)
    expect_authorization_request(context.connection)

    conn = get(build_conn(), "/sso/#{context.organization.name}")
    assert_receive {:sso_state, state, redirect_uri}
    expect_code_exchange(context.connection, state, redirect_uri, primary_email.email)

    conn =
      conn
      |> recycle()
      |> get("/sso/callback", %{state: state, code: "authorization-code"})

    assert redirected_to(conn) == "/sso/confirm"

    %{"transaction_id" => transaction_id, "capability" => capability} =
      get_session(conn, "pending_sso_confirmation")

    {code, _entry} = confirmation_code()

    %{
      conn: conn,
      transaction_id: transaction_id,
      capability: capability,
      code: code
    }
  end

  defp restore_confirmation_fixture(_context, :primary_email, transaction) do
    Repo.update_all(
      from(email in Hexpm.Accounts.Email, where: email.id == ^transaction.candidate_email_id),
      set: [primary: true]
    )
  end

  defp restore_confirmation_fixture(context, :membership, _transaction) do
    insert(:organization_user,
      organization: context.organization,
      user: context.member,
      role: "admin"
    )
  end

  defp restore_confirmation_fixture(_context, :domain, transaction) do
    Repo.update_all(
      from(domain in SSO.Domain, where: domain.id == ^transaction.domain_id),
      set: [
        state: "verified",
        valid_until: DateTime.add(DateTime.utc_now(), 6 * 24 * 60 * 60, :second),
        invalidated_at: nil,
        automatic_linking_enabled: true
      ]
    )
  end

  defp restore_confirmation_fixture(context, :connection, transaction) do
    Repo.update_all(
      from(connection in SSO.Connection, where: connection.id == ^context.connection.id),
      set: [version: transaction.candidate_connection_version]
    )
  end

  defp confirmation_code do
    entry =
      Repo.one!(from(entry in OutboxEntry, where: entry.category == "sso.confirmation_code"))

    %{text_body: body} = OutboxEnvelope.load!(entry.email)
    [code] = Regex.run(~r/\b[A-Z2-7]{10}\b/, body)
    {code, entry}
  end

  defp assert_confirmation_cleared(transaction_id) do
    transaction = Repo.get!(SSO.Transaction, transaction_id)
    assert transaction.cancelled_at
    assert transaction.candidate_user_id == nil
    assert transaction.candidate_email_id == nil
    assert transaction.domain_id == nil
    assert transaction.domain_challenge_generation == nil
    assert transaction.candidate_connection_version == nil
    assert transaction.confirmation_code_hash == nil
    assert transaction.confirmation_expires_at == nil
    assert transaction.confirmation_verified_at == nil
    assert transaction.confirmation_attempts == 0
    assert transaction.confirmation_sends == 0
    assert transaction.browser_capability_hash == nil
    assert transaction.issuer == nil
    assert transaction.subject == nil
    assert transaction.provider_email == nil
    ordering_key = "sso-confirmation:#{transaction_id}"

    refute Repo.exists?(
             from(entry in OutboxEntry,
               where: entry.ordering_key == ^ordering_key,
               where: entry.category == "sso.confirmation_code"
             )
           )
  end

  defp expect_authorization_request(connection, opts \\ []) do
    expected_login_hint = Keyword.get(opts, :login_hint)

    expect(OIDC.Mock, :authorization_uri, fn received_connection,
                                             transaction,
                                             redirect_uri,
                                             client_secret ->
      assert received_connection.id == connection.id
      assert client_secret == connection.client_secret
      assert transaction.redirect_uri == redirect_uri
      assert transaction.login_hint == expected_login_hint
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

  defp begin_pending_login(context) do
    identity =
      insert(:organization_sso_identity,
        connection: context.connection,
        organization: context.organization,
        user: context.member
      )

    expect_authorization_request(context.connection)
    conn = get(build_conn(), "/sso/#{context.organization.name}")
    assert_receive {:sso_state, state, redirect_uri}
    expect_code_exchange(context.connection, state, redirect_uri, identity.provider_email)

    conn =
      conn
      |> recycle()
      |> get("/sso/callback", %{state: state, code: "authorization-code"})

    assert redirected_to(conn) == "/sso/continue"

    %{"transaction_id" => transaction_id, "capability" => capability} =
      get_session(conn, "pending_sso_login")

    %{
      conn: conn,
      identity: identity,
      transaction_id: transaction_id,
      capability: capability
    }
  end

  defp assert_no_store(conn) do
    assert get_resp_header(conn, "cache-control") == ["no-store"]
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
