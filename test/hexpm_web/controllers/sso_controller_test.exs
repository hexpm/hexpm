defmodule HexpmWeb.SSOControllerTest do
  use HexpmWeb.ConnCase
  use Oban.Testing, repo: Hexpm.RepoBase

  import ExUnit.CaptureIO
  import ExUnit.CaptureLog

  alias Hexpm.Accounts.{AuditLogs, SSO}
  alias Hexpm.Accounts.SSO.{Identity, OIDC, OrgSession}
  alias HexpmWeb.Plugs.Attack

  setup :verify_on_exit!

  setup do
    PlugAttack.Storage.Ets.clean(HexpmWeb.Plugs.Attack.Storage)
    stub(Hexpm.Billing.Mock, :get, fn _organization, _opts -> nil end)
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

  describe "no SSO path establishes an account session" do
    # The acceptance criterion in sso.md is an effect, not a function name, so
    # these assert the effect. The structural test below is a supplement that
    # catches a reintroduction earlier, at the call site.
    test "a successful login callback leaves the account session untouched", context do
      identity =
        insert(:organization_sso_identity,
          connection: context.connection,
          organization: context.organization,
          user: context.member
        )

      %{conn: conn, state: state} = begin_login(context)
      before = account_session_fingerprint(conn, context.member)

      conn = complete_callback(conn, state, identity.provider_email)

      assert redirected_to(conn) == "/dashboard/orgs/#{context.organization.name}"
      assert account_session_fingerprint(conn, context.member) == before
    end

    test "a callback handing off to link consent leaves the account session untouched",
         context do
      %{conn: conn, state: state} = begin_login(context)
      before = account_session_fingerprint(conn, context.member)

      conn = complete_callback(conn, state)

      assert redirected_to(conn) == "/sso/link"
      assert account_session_fingerprint(conn, context.member) == before
    end

    test "consenting to a link leaves the account session untouched", context do
      %{conn: conn, state: state} = begin_login(context)
      conn = complete_callback(conn, state)

      conn = conn |> recycle() |> test_login(context.member)
      before = account_session_fingerprint(conn, context.member)

      conn = post(conn, "/sso/link")

      assert redirected_to(conn) == "/dashboard/orgs/#{context.organization.name}"
      assert account_session_fingerprint(conn, context.member) == before
    end

    test "a callback for a linked identity in a session-less browser mints nothing", context do
      insert(:organization_sso_identity,
        connection: context.connection,
        organization: context.organization,
        user: context.member
      )

      %{conn: conn, state: state} = begin_login(context)
      sessions_before = Repo.aggregate(Hexpm.UserSession, :count)

      conn =
        conn
        |> session_less_conn()
        |> get("/sso/callback", %{state: state, code: "authorization-code"})

      assert redirected_to(conn) == "/login"
      refute get_session(conn, "session_token")
      refute Repo.exists?(OrgSession)
      assert Repo.aggregate(Hexpm.UserSession, :count) == sessions_before
    end

    test "the SSO namespace never calls the session-minting function" do
      for module <- sso_modules() do
        {:ok, {^module, [{:abstract_code, {:raw_abstract_v1, abstract_code}}]}} =
          module |> :code.which() |> :beam_lib.chunks([:abstract_code])

        refute mints_account_session?(abstract_code),
               "#{inspect(module)} reaches a session-minting function"
      end
    end

    test "the structural check detects every reintroduction shape it claims to" do
      # A detector nobody has tried to fool is a detector that passes for free.
      # These are the shapes a regression would plausibly take.
      previous = Code.get_compiler_option(:debug_info)
      Code.put_compiler_option(:debug_info, true)
      on_exit(fn -> Code.put_compiler_option(:debug_info, previous) end)

      caught? = fn body ->
        module = :"Elixir.SSOProbe#{System.unique_integer([:positive])}"

        # Probes are deliberately odd shapes; their warnings are noise.
        {[{^module, binary}], _warnings} =
          with_io(:stderr, fn ->
            Code.compile_string("""
            defmodule #{inspect(module)} do
              import HexpmWeb.ControllerHelpers, only: [start_session_internal: 2]
              @helpers HexpmWeb.ControllerHelpers
              def run(conn, user) do
                _ = {conn, user, @helpers}
                #{body}
              end
            end
            """)
          end)

        {:ok, {^module, [{:abstract_code, {:raw_abstract_v1, code}}]}} =
          :beam_lib.chunks(binary, [:abstract_code])

        :code.purge(module)
        :code.delete(module)
        mints_account_session?(code)
      end

      assert caught?.("start_session_internal(conn, user)")
      assert caught?.("HexpmWeb.ControllerHelpers.start_session_internal(conn, user)")
      assert caught?.("apply(HexpmWeb.ControllerHelpers, :start_session_internal, [conn, user])")
      assert caught?.("apply(@helpers, :start_session_internal, [conn, user])")
      assert caught?.("(&HexpmWeb.ControllerHelpers.start_session_internal/2).(conn, user)")

      assert caught?.("""
             {:ok, _s, token} = Hexpm.UserSessions.create_browser_session(user, audit: nil)
             Plug.Conn.put_session(conn, "session_token", Base.encode64(token))
             """)

      refute caught?.("Plug.Conn.put_session(conn, \"unrelated\", user.id)")
    end
  end

  describe "start requires an account session" do
    test "an unauthenticated start reaches login with the return path intact", context do
      conn = get(build_conn(), "/sso/org/#{context.organization.name}")

      assert redirected_to(conn) ==
               "/login?return=%2Fsso%2Forg%2F#{context.organization.name}"

      refute Repo.exists?(SSO.Transaction)
    end

    test "third-party initiation parameters survive the login detour", context do
      query =
        URI.encode_query(%{
          "iss" => context.connection.issuer,
          "login_hint" => "guest@example.com"
        })

      conn = get(build_conn(), "/sso/org/#{context.organization.name}?#{query}")

      assert %URI{path: "/login", query: login_query} =
               conn |> redirected_to() |> URI.parse()

      assert %{"return" => return} = URI.decode_query(login_query)
      assert return == "/sso/org/#{context.organization.name}?#{query}"
      refute Repo.exists?(SSO.Transaction)
    end

    test "a signed-in nonmember is refused before the provider round trip", context do
      outsider = insert(:user)

      conn =
        build_conn()
        |> test_login(outsider)
        |> get("/sso/org/#{context.organization.name}")

      assert redirected_to(conn) == "/dashboard"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "not a member"
      refute Repo.exists?(SSO.Transaction)
    end

    test "a signed-in member starts a transaction bound to that account", context do
      expect_authorization_request(context.connection)

      conn =
        build_conn()
        |> test_login(context.member)
        |> get("/sso/org/#{context.organization.name}")

      assert redirected_to(conn) =~ "https://identity.example.com/authorize"
      assert_no_store(conn)

      transaction = Repo.one!(SSO.Transaction)
      assert transaction.user_id == context.member.id
      assert transaction.entrypoint == "organization"
    end
  end

  describe "callback outcome: unlinked subject" do
    test "a member is handed to the link consent page", context do
      %{conn: conn, state: state} = begin_login(context)

      conn = complete_callback(conn, state)

      assert redirected_to(conn) == "/sso/link"
      assert %{"transaction_id" => _id, "token" => _token} = get_session(conn, "pending_sso_link")
      refute Repo.exists?(Identity)

      conn = conn |> recycle() |> test_login(context.member) |> get("/sso/link")
      assert html_response(conn, 200) =~ "Connect organization SSO"
    end

    test "consenting links the identity and returns to the organization", context do
      %{conn: conn, state: state} = begin_login(context)
      conn = complete_callback(conn, state)

      conn =
        conn
        |> recycle()
        |> test_login(context.member)
        |> post("/sso/link")

      assert redirected_to(conn) == "/dashboard/orgs/#{context.organization.name}"

      identity = Repo.one!(Identity)
      assert identity.user_id == context.member.id
      assert identity.connection_id == context.connection.id

      # Consent completes an authentication seconds old, so it unlocks the
      # organization rather than making the member do the round trip twice.
      org_session = Repo.one!(OrgSession)
      assert org_session.identity_id == identity.id
      assert org_session.user_id == context.member.id
    end

    test "a nonmember is refused and nothing is created", context do
      outsider = insert(:user)
      insert(:organization_user, organization: context.organization, user: outsider)
      %{conn: conn, state: state} = begin_login(context, user: outsider)

      Repo.delete_all(
        from(organization_user in Hexpm.Accounts.OrganizationUser,
          where: organization_user.user_id == ^outsider.id
        )
      )

      conn = complete_callback(conn, state)

      assert redirected_to(conn) == "/dashboard"
      refute Repo.exists?(Identity)
      refute get_session(conn, "pending_sso_link")
      assert [%{code: "not_member"}] = SSO.failures(context.connection)
    end
  end

  describe "callback outcome: linked subject owned by the signed-in account" do
    setup context do
      identity =
        insert(:organization_sso_identity,
          connection: context.connection,
          organization: context.organization,
          user: context.member
        )

      Map.put(context, :identity, identity)
    end

    test "establishes an organization access session and audits the login", context do
      %{conn: conn, state: state} = begin_login(context)

      conn = complete_callback(conn, state, context.identity.provider_email)

      assert redirected_to(conn) == "/dashboard/orgs/#{context.organization.name}"
      refute get_session(conn, "pending_sso_link")

      org_session = Repo.one!(OrgSession)
      assert org_session.user_id == context.member.id
      assert org_session.organization_id == context.organization.id
      assert org_session.identity_id == context.identity.id
      assert org_session.revoked_at == nil
      assert DateTime.compare(org_session.expires_at, DateTime.utc_now()) == :gt

      assert [audit] =
               AuditLogs.all_by(context.organization, 1, 100) |> filter_action("sso.login")

      assert audit.params["user_id"] == context.member.id
    end

    test "re-authenticating in the same browser session refreshes one row", context do
      %{conn: conn, state: state} = begin_login(context)
      conn = complete_callback(conn, state, context.identity.provider_email)
      first = Repo.one!(OrgSession)

      expect_authorization_request(context.connection)
      conn = conn |> recycle() |> get("/sso/org/#{context.organization.name}")
      assert_receive {:sso_state, state, redirect_uri}
      expect_code_exchange(context.connection, state, redirect_uri, nil)

      conn
      |> recycle()
      |> get("/sso/callback", %{state: state, code: "authorization-code"})

      second = Repo.one!(OrgSession)
      assert second.id == first.id
      assert DateTime.compare(second.authenticated_at, first.authenticated_at) != :lt
    end

    test "the dashboard shows the current authentication and its expiry", context do
      %{conn: conn, state: state} = begin_login(context)
      conn = complete_callback(conn, state, context.identity.provider_email)

      conn =
        conn
        |> recycle()
        |> get("/dashboard/orgs/#{context.organization.name}")

      body = html_response(conn, 200)
      assert body =~ "sso-org-session"
      assert body =~ "through single sign-on until"
    end
  end

  describe "callback outcome: refusals" do
    test "a subject owned by another account refuses and touches neither", context do
      other = insert(:user)
      insert(:organization_user, organization: context.organization, user: other)

      identity =
        insert(:organization_sso_identity,
          connection: context.connection,
          organization: context.organization,
          user: other
        )

      %{conn: conn, state: state} = begin_login(context)
      conn = complete_callback(conn, state, identity.provider_email)

      assert redirected_to(conn) == "/dashboard"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "session_user_mismatch"

      assert [%Identity{} = unchanged] = Repo.all(Identity)
      assert unchanged.id == identity.id
      assert unchanged.user_id == other.id
      assert unchanged.subject == identity.subject
      assert unchanged.provider_email == identity.provider_email
      refute Repo.exists?(OrgSession)

      # An admin needs to see this one; it is how a claimed subject is diagnosed.
      assert [%{stage: "login", code: "session_user_mismatch", user_id: user_id}] =
               SSO.failures(context.connection)

      assert user_id == context.member.id

      refute Enum.any?(
               AuditLogs.all_by(context.organization, 1, 100),
               &(&1.action == "sso.login")
             )
    end

    test "the signed-in account holding a different subject refuses", context do
      insert(:organization_sso_identity,
        connection: context.connection,
        organization: context.organization,
        user: context.member,
        subject: "00u-original"
      )

      %{conn: conn, state: state} = begin_login(context)
      conn = complete_callback(conn, state, nil, "00u-different")

      assert redirected_to(conn) == "/dashboard"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "identity_conflict"
      assert [%Identity{subject: "00u-original"}] = Repo.all(Identity)
      refute Repo.exists?(OrgSession)

      assert [%{stage: "login", code: "identity_conflict", user_id: user_id}] =
               SSO.failures(context.connection)

      assert user_id == context.member.id
    end

    test "signing in as a different account mid-flow refuses", context do
      other = insert(:user)
      insert(:organization_user, organization: context.organization, user: other)
      %{conn: conn, state: state, redirect_uri: redirect_uri} = begin_login(context)
      expect_code_exchange(context.connection, state, redirect_uri, nil)

      conn =
        conn
        |> recycle()
        |> test_login(other)
        |> get("/sso/callback", %{state: state, code: "authorization-code"})

      assert redirected_to(conn) == "/dashboard"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "session_user_mismatch"
      refute Repo.exists?(Identity)
      refute Repo.exists?(OrgSession)
    end

    test "a linked identity belonging to a nonmember is deleted and refused", context do
      insert(:organization_sso_identity,
        connection: context.connection,
        organization: context.organization,
        user: context.member
      )

      %{conn: conn, state: state} = begin_login(context)

      Repo.delete_all(
        from(organization_user in Hexpm.Accounts.OrganizationUser,
          where: organization_user.user_id == ^context.member.id,
          where: organization_user.organization_id == ^context.organization.id
        )
      )

      conn = complete_callback(conn, state)

      assert redirected_to(conn) == "/dashboard"
      refute Repo.exists?(Identity)
      refute Repo.exists?(OrgSession)
      assert [%{code: "not_member"}] = SSO.failures(context.connection)
    end

    test "losing the account session mid-flow ends the attempt", context do
      insert(:organization_sso_identity,
        connection: context.connection,
        organization: context.organization,
        user: context.member
      )

      %{conn: conn, state: state} = begin_login(context)

      conn =
        conn
        |> session_less_conn()
        |> get("/sso/callback", %{state: state, code: "authorization-code"})

      assert redirected_to(conn) == "/login"
      refute get_session(conn, "session_token")
      refute Repo.exists?(OrgSession)
      assert Repo.one!(SSO.Transaction).consumed_at
      assert [%{code: "account_session_required"}] = SSO.failures(context.connection)
    end
  end

  describe "organization access session lifetime" do
    setup context do
      identity =
        insert(:organization_sso_identity,
          connection: context.connection,
          organization: context.organization,
          user: context.member
        )

      %{conn: conn, state: state} = begin_login(context)
      conn = complete_callback(conn, state, identity.provider_email)

      Map.merge(context, %{conn: conn, identity: identity})
    end

    test "signing out revokes it", context do
      context.conn
      |> recycle()
      |> post("/logout")

      assert Repo.one!(OrgSession).revoked_at
    end

    test "removing the member deletes it", context do
      insert(:organization_user, organization: context.organization, user: insert(:user))

      Hexpm.Accounts.Organizations.remove_member(
        context.organization,
        context.member,
        audit: audit_data(context.member)
      )

      refute Repo.exists?(OrgSession)
      refute Repo.exists?(Identity)
    end

    test "an admin unlink deletes it", context do
      SSO.unlink_identity(context.organization, context.member, audit: audit_data(context.member))

      refute Repo.exists?(OrgSession)
      refute Repo.exists?(Identity)
    end

    test "the settings tab shows when the member last authenticated", context do
      conn =
        build_conn()
        |> test_login(context.member)
        |> get("/dashboard/orgs/#{context.organization.name}/sso")

      assert html_response(conn, 200) =~ "Last authenticated"
    end
  end

  describe "personal two-factor authentication" do
    test "is prompted at Hexpm login and neither skipped nor repeated by SSO", context do
      member = insert(:user, tfa: build(:tfa))
      insert(:organization_user, organization: context.organization, user: member)

      identity =
        insert(:organization_sso_identity,
          connection: context.connection,
          organization: context.organization,
          user: member
        )

      mock_pwned()

      # Hexpm login stops at TFA and mints no session yet.
      conn =
        post(build_conn(), "/login", %{
          username: member.username,
          password: "password",
          return: "/sso/org/#{context.organization.name}"
        })

      assert redirected_to(conn) == "/tfa"
      refute get_session(conn, "session_token")

      token = Hexpm.Accounts.TFA.time_based_token(member.tfa.secret)
      conn = conn |> recycle() |> post("/tfa", %{code: token})

      assert redirected_to(conn) == "/sso/org/#{context.organization.name}"
      assert get_session(conn, "session_token")

      # The SSO step that follows never prompts for TOTP again and never
      # re-enters the TFA flow.
      expect_authorization_request(context.connection)
      conn = conn |> recycle() |> get("/sso/org/#{context.organization.name}")
      assert_receive {:sso_state, state, redirect_uri}
      expect_code_exchange(context.connection, state, redirect_uri, identity.provider_email)

      conn =
        conn
        |> recycle()
        |> get("/sso/callback", %{state: state, code: "authorization-code"})

      assert redirected_to(conn) == "/dashboard/orgs/#{context.organization.name}"
      refute get_session(conn, "tfa_user_id")
      assert Repo.one!(OrgSession).user_id == member.id
    end
  end

  describe "third-party initiation" do
    setup context do
      Map.put(context, :conn, test_login(build_conn(), context.member))
    end

    test "accepts organization-bound initiation without persisting the login hint", context do
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

      conn = get(context.conn, "/sso/org/#{context.organization.name}?#{query}")

      assert redirected_to(conn) =~ "https://identity.example.com/authorize"
      assert_no_store(conn)

      transaction = Repo.one!(SSO.Transaction)
      assert transaction.entrypoint == "third_party"
      assert transaction.return_path == target_path
      assert transaction.login_hint == nil
    end

    test "ignores unknown parameters as a conventional organization start", context do
      expect_authorization_request(context.connection)

      conn =
        get(
          context.conn,
          "/sso/org/#{context.organization.name}?unknown=first&unknown=second"
        )

      assert redirected_to(conn) =~ "https://identity.example.com/authorize"
      assert Repo.one!(SSO.Transaction).entrypoint == "organization"
    end

    test "rejects duplicate recognized parameters before transaction creation", context do
      query =
        "iss=#{URI.encode_www_form(context.connection.issuer)}&iss=#{URI.encode_www_form(context.connection.issuer)}"

      conn = get(context.conn, "/sso/org/#{context.organization.name}?#{query}")

      assert redirected_to(conn) == "/dashboard"
      refute Repo.exists?(SSO.Transaction)
    end

    test "requires the exact issuer", context do
      query = URI.encode_query(%{"iss" => "https://attacker.example.com"})
      conn = get(context.conn, "/sso/org/#{context.organization.name}?#{query}")

      assert redirected_to(conn) == "/dashboard"
      refute Repo.exists?(SSO.Transaction)
    end

    test "rejects cross-origin and non-dashboard target link URIs", context do
      for target <- [
            "https://attacker.example.com/dashboard/orgs/#{context.organization.name}",
            "http://localhost:5000/dashboard/orgs/other",
            "http://localhost:5000/packages"
          ] do
        query =
          URI.encode_query(%{
            "iss" => context.connection.issuer,
            "target_link_uri" => target
          })

        conn = get(context.conn, "/sso/org/#{context.organization.name}?#{query}")

        assert redirected_to(conn) == "/dashboard"
        refute Repo.exists?(SSO.Transaction)
      end
    end
  end

  describe "route exposure and logging" do
    test "an empty beta allowlist hides every public SSO route", context do
      config = Application.fetch_env!(:hexpm, :organization_sso)

      app_env(
        :hexpm,
        :organization_sso,
        Keyword.merge(config, mode: :beta, beta_organizations: [])
      )

      build_conn() |> get("/sso/org/#{context.organization.name}") |> response(404)
      build_conn() |> get("/sso/callback", %{state: "unknown", code: "code"}) |> response(404)
      build_conn() |> get("/sso/link") |> response(404)
      build_conn() |> post("/sso/link") |> response(404)
      build_conn() |> post("/sso/link/cancel") |> response(404)
    end

    test "the removed and legacy routes are gone", context do
      conn = test_login(build_conn(), context.member)

      for path <- [
            "/sso/discover",
            "/sso/confirm",
            "/sso/continue",
            "/sso/#{context.organization.name}"
          ] do
        assert response(get(conn, path), 404)
      end

      # The organization link is only ever the /org/ form.
      expect_authorization_request(context.connection)
      conn = get(conn, "/sso/org/#{context.organization.name}")
      assert redirected_to(conn) =~ "https://identity.example.com/authorize"
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
  end

  describe "rate limiting and state binding" do
    test "rate limits starts per IP before inserting a transaction", context do
      ip = {198, 51, 100, 42}
      time = System.system_time(:millisecond)

      for _attempt <- 1..30 do
        assert {:allow, _data} = Attack.sso_start_ip_throttle(ip, time: time)
      end

      conn =
        build_conn()
        |> Map.put(:remote_ip, ip)
        |> test_login(context.member)
        |> get("/sso/org/#{context.organization.name}")

      assert response(conn, 429) =~ "Too many SSO login attempts"
      refute Repo.exists?(SSO.Transaction)
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
        |> get("/sso/callback", %{state: "any", code: "any"})

      assert response(conn, 429) =~ "Too many SSO callback attempts"
    end

    test "callback state is bound to the browser that started the transaction", context do
      %{state: state} = begin_login(context)

      conn =
        build_conn()
        |> test_login(context.member)
        |> get("/sso/callback", %{state: state, code: "authorization-code"})

      assert redirected_to(conn) == "/dashboard"
      refute Repo.exists?(Identity)
      refute Repo.one!(SSO.Transaction).consumed_at
    end

    test "a consumed state cannot be replayed", context do
      %{conn: conn, state: state} = begin_login(context)
      conn = complete_callback(conn, state)
      assert redirected_to(conn) == "/sso/link"
      assert Repo.one!(SSO.Transaction).consumed_at

      # forget_sso_state/2 dropped the binding, so the replay cannot even reach
      # the transaction; it must not be mistaken for a live one.
      replayed =
        conn
        |> recycle()
        |> test_login(context.member)
        |> get("/sso/callback", %{state: state, code: "authorization-code"})

      assert redirected_to(replayed) == "/dashboard"
      assert Phoenix.Flash.get(replayed.assigns.flash, :error) =~ "invalid_state"
      assert Repo.aggregate(Identity, :count) == 0
    end

    test "a provider error consumes the transaction and records the reason", context do
      %{conn: conn, state: state} = begin_login(context)

      conn =
        conn
        |> recycle()
        |> get("/sso/callback", %{state: state, error: "access_denied"})

      assert redirected_to(conn) == "/dashboard"
      assert Repo.one!(SSO.Transaction).consumed_at

      assert [%{stage: "authorization", code: "provider_error"}] =
               SSO.failures(context.connection)
    end
  end

  # A browser that still holds the SSO state binding but no account session,
  # which is what signing out mid-flow leaves behind.
  defp session_less_conn(conn) do
    Plug.Test.init_test_session(build_conn(), %{"sso_states" => get_session(conn, "sso_states")})
  end

  defp begin_login(context, opts \\ []) do
    user = Keyword.get(opts, :user, context.member)
    expect_authorization_request(context.connection)

    conn =
      build_conn()
      |> test_login(user)
      |> get("/sso/org/#{context.organization.name}")

    assert_receive {:sso_state, state, redirect_uri}
    %{conn: conn, state: state, redirect_uri: redirect_uri, user: user}
  end

  defp complete_callback(conn, state, email \\ nil, subject \\ "00u123") do
    expect(OIDC.Mock, :exchange_code, fn connection, transaction, code, redirect_uri, secret ->
      assert transaction.state_hash == :crypto.hash(:sha256, state)
      assert code == "authorization-code"
      assert redirect_uri == transaction.redirect_uri
      assert secret == connection.client_secret

      {:ok, %{issuer: connection.issuer, subject: subject, email: email, jwks_document: nil}}
    end)

    conn
    |> recycle()
    |> get("/sso/callback", %{state: state, code: "authorization-code"})
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

  defp filter_action(audit_logs, action) do
    Enum.filter(audit_logs, &(&1.action == action))
  end

  defp assert_no_store(conn) do
    assert get_resp_header(conn, "cache-control") == ["no-store"]
  end

  # The list is derived, not hardcoded: a new module under the SSO namespace is
  # covered the day it is created.
  defp sso_modules do
    {:ok, modules} = :application.get_key(:hexpm, :modules)

    Enum.filter(modules, fn module ->
      name = Atom.to_string(module)

      String.starts_with?(name, "Elixir.Hexpm.Accounts.SSO") or
        String.starts_with?(name, "Elixir.HexpmWeb.SSO") or
        String.starts_with?(name, "Elixir.HexpmWeb.Dashboard.OrganizationSSO")
    end)
  end

  # Anything that would hand the browser an account session: the helper itself,
  # however it is reached, or the two primitives it is built from.
  @minting_functions [:start_session_internal, :create_browser_session]

  defp mints_account_session?(abstract_code) do
    find_minting_call(abstract_code) or writes_session_token?(abstract_code)
  end

  # Direct or imported call.
  defp find_minting_call({:call, _anno, {:atom, _, name}, _args})
       when name in @minting_functions,
       do: true

  # Remote call through a module name or an alias.
  defp find_minting_call({:call, _anno, {:remote, _, _mod, {:atom, _, name}}, _args})
       when name in @minting_functions,
       do: true

  # apply/3, whether the module is a literal or a variable.
  defp find_minting_call(
         {:call, _anno, {:remote, _, {:atom, _, :erlang}, {:atom, _, :apply}},
          [_mod, {:atom, _, name}, _args]}
       )
       when name in @minting_functions,
       do: true

  # Captured function, &Mod.fun/2.
  defp find_minting_call({:fun, _anno, {:function, _mod, {:atom, _, name}, _arity}})
       when name in @minting_functions,
       do: true

  defp find_minting_call(term) when is_tuple(term),
    do: term |> Tuple.to_list() |> find_minting_call()

  defp find_minting_call(list) when is_list(list),
    do: Enum.any?(list, &find_minting_call/1)

  defp find_minting_call(_term), do: false

  # The primitives can be inlined; writing the session key is the giveaway.
  defp writes_session_token?({:bin, _anno, segments} = term) do
    segments
    |> Enum.map(fn
      {:bin_element, _, {:string, _, chars}, _, _} -> List.to_string(chars)
      _other -> ""
    end)
    |> Enum.join()
    |> Kernel.==("session_token")
    |> Kernel.or(deep_any?(term, &writes_session_token?/1))
  end

  defp writes_session_token?(term) when is_tuple(term) or is_list(term),
    do: deep_any?(term, &writes_session_token?/1)

  defp writes_session_token?(_term), do: false

  defp deep_any?(term, fun) when is_tuple(term), do: term |> Tuple.to_list() |> deep_any?(fun)
  defp deep_any?(list, fun) when is_list(list), do: Enum.any?(list, fun)
  defp deep_any?(_term, _fun), do: false

  # A stable summary of everything that would change if SSO touched the account
  # session: the cookie value, the row count, and the sudo timestamp.
  defp account_session_fingerprint(conn, user) do
    %{
      session_token: get_session(conn, "session_token"),
      sudo_at: get_session(conn, "sudo_authenticated_at"),
      session_count:
        Repo.aggregate(
          from(session in Hexpm.UserSession, where: session.user_id == ^user.id),
          :count
        )
    }
  end
end
