defmodule Hexpm.Accounts.SSO.EnforcementTest do
  use Hexpm.DataCase

  alias Hexpm.Accounts.SSO
  alias Hexpm.Accounts.SSO.Enforcement

  setup do
    organization = insert(:organization)
    admin = insert(:user)
    member = insert(:user)
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

    %{organization: organization, admin: admin, member: member, connection: connection}
  end

  describe "mode/3" do
    test "is optional without a connection", %{organization: organization} do
      assert Enforcement.mode(organization, nil) == :optional
    end

    test "is optional while the connection is disabled", context do
      connection = %{context.connection | enabled_at: nil, enforcement_mode: "required"}

      assert Enforcement.mode(context.organization, connection) == :optional
    end

    test "is optional for an organization outside the beta allowlist", context do
      config = Application.fetch_env!(:hexpm, :organization_sso)
      Application.put_env(:hexpm, :organization_sso, Keyword.put(config, :beta_organizations, []))

      connection = %{context.connection | enforcement_mode: "required"}

      assert Enforcement.mode(context.organization, connection) == :optional
    end

    test "follows the configured mode", context do
      for mode <- ~w(optional pilot) do
        connection = %{context.connection | enforcement_mode: mode}
        assert Enforcement.mode(context.organization, connection) == String.to_atom(mode)
      end
    end

    test "reads as pilot until the required date passes", context do
      now = DateTime.utc_now()

      connection = %{
        context.connection
        | enforcement_mode: "required",
          required_at: DateTime.add(now, 60, :second),
          personal_keys: "block"
      }

      assert Enforcement.mode(context.organization, connection, now) == :pilot

      assert Enforcement.mode(
               context.organization,
               connection,
               DateTime.add(now, 120, :second)
             ) == :required
    end

    test "flips on the timestamp with no job having run", context do
      link_identity(context, context.admin)

      {:ok, connection} =
        configure(context, %{
          "enforcement_mode" => "required",
          "required_at" => DateTime.add(DateTime.utc_now(), 3_600, :second),
          "personal_keys" => "block"
        })

      assert Enforcement.mode(context.organization, connection) == :pilot

      # Nothing promotes the row. The mode is a function of the clock, so a job
      # that never ran cannot leave an organization unenforced past its date.
      assert Enforcement.mode(
               context.organization,
               connection,
               DateTime.add(connection.required_at, 1, :second)
             ) == :required
    end
  end

  describe "governed?/3" do
    test "optional mode governs nobody", context do
      connection = %{context.connection | enforcement_mode: "optional"}

      for enforcement <- [nil, "enforced", "exempt"] do
        refute Enforcement.governed?(context.organization, connection, enforcement)
      end
    end

    test "pilot governs only the members marked enforced", context do
      connection = %{context.connection | enforcement_mode: "pilot"}

      assert Enforcement.governed?(context.organization, connection, "enforced")
      refute Enforcement.governed?(context.organization, connection, nil)
      refute Enforcement.governed?(context.organization, connection, "exempt")
    end

    test "required governs everyone but the exemptions", context do
      connection = %{
        context.connection
        | enforcement_mode: "required",
          required_at: DateTime.add(DateTime.utc_now(), -60, :second),
          personal_keys: "block"
      }

      assert Enforcement.governed?(context.organization, connection, nil)
      assert Enforcement.governed?(context.organization, connection, "enforced")
      refute Enforcement.governed?(context.organization, connection, "exempt")
    end

    test "a member enforced during a pilot stays enforced in required mode", context do
      pilot = %{context.connection | enforcement_mode: "pilot"}

      required = %{
        context.connection
        | enforcement_mode: "required",
          required_at: DateTime.add(DateTime.utc_now(), -60, :second),
          personal_keys: "block"
      }

      # The trap a single boolean would have set: the people you piloted with
      # would become the only ones exempt on the way to required mode.
      assert Enforcement.governed?(context.organization, pilot, "enforced")
      assert Enforcement.governed?(context.organization, required, "enforced")
    end
  end

  describe "session_lifetime/1" do
    test "defaults to 24 hours without a connection" do
      assert Enforcement.session_lifetime(nil) == 86_400
    end

    test "follows the connection", context do
      assert Enforcement.session_lifetime(context.connection) == 86_400

      {:ok, connection} = configure(context, %{"session_lifetime_seconds" => 3_600})

      assert Enforcement.session_lifetime(connection) == 3_600
    end

    test "governs the session an authentication establishes", context do
      {:ok, _connection} = configure(context, %{"session_lifetime_seconds" => 3_600})

      identity =
        insert(:organization_sso_identity,
          connection: context.connection,
          organization: context.organization,
          user: context.member
        )

      session = browser_session(context.member)

      org_session = SSO.establish_org_session!(identity, session.id)

      assert_in_delta DateTime.diff(org_session.expires_at, org_session.authenticated_at),
                      3_600,
                      2
    end
  end

  describe "check/4" do
    test "passes a member of an optional organization", context do
      session = browser_session(context.member)

      assert Enforcement.check(context.organization, context.member, nil, session.id) == :ok
    end

    test "refuses a governed member who has not authenticated", context do
      {:ok, _connection} = require_sso(context)
      session = browser_session(context.member)

      assert Enforcement.check(context.organization, context.member, nil, session.id) ==
               {:error, :sso_required}
    end

    test "passes once the member has authenticated on that session", context do
      {:ok, _connection} = require_sso(context)
      session = browser_session(context.member)
      authenticate(context, context.member, session)

      assert Enforcement.check(context.organization, context.member, nil, session.id) == :ok
    end

    test "is per browser session, not per account", context do
      {:ok, _connection} = require_sso(context)
      authenticated = browser_session(context.member)
      other = browser_session(context.member)
      authenticate(context, context.member, authenticated)

      assert Enforcement.check(context.organization, context.member, nil, authenticated.id) == :ok

      assert Enforcement.check(context.organization, context.member, nil, other.id) ==
               {:error, :sso_required}
    end

    test "treats an expired session as no session", context do
      {:ok, _connection} = require_sso(context)
      session = browser_session(context.member)
      org_session = authenticate(context, context.member, session)

      org_session
      |> Ecto.Changeset.change(expires_at: DateTime.add(DateTime.utc_now(), -1, :second))
      |> Repo.update!()

      assert Enforcement.check(context.organization, context.member, nil, session.id) ==
               {:error, :sso_required}
    end

    test "reads an OAuth token's own session rather than the browser's", context do
      {:ok, _connection} = require_sso(context)
      browser = browser_session(context.member)
      oauth = oauth_session(context.member)
      authenticate(context, context.member, oauth)

      # The browser session is the one in hand and is not authenticated. The
      # token carries its own, which is.
      assert Enforcement.check(context.organization, context.member, token(oauth), browser.id) ==
               :ok

      assert Enforcement.check(context.organization, context.member, token(browser), browser.id) ==
               {:error, :sso_required}
    end

    test "refuses a credential that holds no session at all", context do
      {:ok, _connection} = require_sso(context)

      # Basic auth has nothing for an organization access session to attach to.
      assert Enforcement.check(context.organization, context.member) ==
               {:error, :sso_required}
    end

    test "leaves a personal key alone where the organization allows them", context do
      link_identity(context, context.admin)

      {:ok, _connection} =
        configure(context, %{"enforcement_mode" => "required", "personal_keys" => "allow"})

      assert Enforcement.check(
               context.organization,
               context.member,
               personal_key(context.member)
             ) == :ok
    end

    test "never governs an organization-owned credential", context do
      {:ok, _connection} = require_sso(context)

      assert Enforcement.check(context.organization, context.organization) == :ok
    end

    test "skips an exempt member", context do
      {:ok, _connection} = require_sso(context)

      {:ok, _member} =
        SSO.set_member_enforcement(context.organization, context.member, "exempt",
          audit: audit_data(context.admin)
        )

      assert Enforcement.check(context.organization, context.member) == :ok
    end

    test "passes for nobody", context do
      {:ok, _connection} = require_sso(context)

      assert Enforcement.check(context.organization, nil) == :ok
    end

    test "refuses a personal key and names a credential that works", context do
      {:ok, _connection} = require_sso(context)

      assert Enforcement.check(
               context.organization,
               context.member,
               personal_key(context.member)
             ) == {:error, :personal_key}

      message = Enforcement.refusal_message(:personal_key, context.organization)
      assert message =~ "does not accept personal API keys"
      assert message =~ "organization key"
      assert message =~ "mix hex.user auth"
    end

    test "points a refused member at their provider", context do
      message = Enforcement.refusal_message(:sso_required, context.organization)

      assert message =~ "/sso/org/#{context.organization.name}"
    end

    test "never governs the public repository", context do
      {:ok, _connection} = require_sso(context)

      assert Enforcement.check(Hexpm.Repository.Repository.hexpm().organization, context.member) ==
               :ok
    end

    test "never governs a service account", context do
      {:ok, _connection} = require_sso(context)
      service = insert(:user, service: true)
      insert(:organization_user, organization: context.organization, user: service, role: "read")

      assert Enforcement.check(context.organization, service) == :ok
    end

    test "leaves an organization the caller is not a member of alone", context do
      {:ok, _connection} = require_sso(context)

      assert Enforcement.check(context.organization, insert(:user)) == :ok
    end
  end

  describe "personal_key_refused/1" do
    test "names the organizations that turn personal keys away", context do
      {:ok, _connection} = require_sso(context)

      assert [organization] = Enforcement.personal_key_refused(context.member)
      assert organization.id == context.organization.id
    end

    test "is empty while the organization allows them", context do
      link_identity(context, context.admin)

      {:ok, _connection} =
        configure(context, %{"enforcement_mode" => "required", "personal_keys" => "allow"})

      assert Enforcement.personal_key_refused(context.member) == []
    end

    test "is empty during the grace period", context do
      link_identity(context, context.admin)

      {:ok, _connection} =
        configure(context, %{
          "enforcement_mode" => "required",
          "required_at" => DateTime.add(DateTime.utc_now(), 3_600, :second),
          "personal_keys" => "block"
        })

      assert Enforcement.personal_key_refused(context.member) == []
    end

    test "is empty for an organization", context do
      assert Enforcement.personal_key_refused(context.organization) == []
    end
  end

  describe "break_glass/3" do
    test "audits and mails the administrators once an hour", context do
      {:ok, _connection} = require_sso(context)

      for _ <- 1..3 do
        Enforcement.break_glass(
          context.organization,
          context.member,
          :billing,
          audit_data(context.member)
        )
      end

      logs =
        Hexpm.Accounts.AuditLogs.all_by(context.organization)
        |> Enum.filter(&(&1.action == "sso.break_glass"))

      assert [log] = logs
      assert log.params["screen"] == "billing"

      assert [entry] =
               Repo.all(
                 from(e in Hexpm.Emails.OutboxEntry, where: e.category == "sso.break_glass")
               )

      assert entry.scope_key == "sso:organization:#{context.organization.id}"
    end

    test "audits again once the window has passed", context do
      {:ok, _connection} = require_sso(context)

      Enforcement.break_glass(
        context.organization,
        context.member,
        :sso,
        audit_data(context.member)
      )

      Repo.update_all(
        from(log in Hexpm.Accounts.AuditLog, where: log.action == "sso.break_glass"),
        set: [inserted_at: DateTime.add(DateTime.utc_now(), -2 * 60 * 60, :second)]
      )

      Enforcement.break_glass(
        context.organization,
        context.member,
        :sso,
        audit_data(context.member)
      )

      logs =
        Hexpm.Accounts.AuditLogs.all_by(context.organization)
        |> Enum.filter(&(&1.action == "sso.break_glass"))

      assert length(logs) == 2
    end
  end

  describe "configure_enforcement/3" do
    test "cannot require SSO without saying what happens to personal keys", context do
      link_identity(context, context.admin)

      assert {:error, changeset} = configure(context, %{"enforcement_mode" => "required"})
      assert errors_on(changeset).personal_keys == "must be chosen before requiring SSO"
    end

    test "requires an administrator who can still get in", context do
      assert {:error, :no_reachable_admin} =
               configure(context, %{
                 "enforcement_mode" => "required",
                 "personal_keys" => "block"
               })
    end

    test "accepts an exempt administrator as reachable", context do
      {:ok, _member} =
        SSO.set_member_enforcement(context.organization, context.admin, "exempt",
          audit: audit_data(context.admin)
        )

      assert {:ok, connection} =
               configure(context, %{
                 "enforcement_mode" => "required",
                 "personal_keys" => "allow"
               })

      assert connection.enforcement_mode == "required"
      assert connection.personal_keys == "allow"
    end

    test "accepts a linked administrator as reachable", context do
      link_identity(context, context.admin)

      assert {:ok, connection} =
               configure(context, %{
                 "enforcement_mode" => "required",
                 "personal_keys" => "block"
               })

      assert connection.enforcement_mode == "required"
    end

    test "stamps required_at when the admin did not pick a date", context do
      link_identity(context, context.admin)

      assert {:ok, connection} =
               configure(context, %{
                 "enforcement_mode" => "required",
                 "personal_keys" => "block"
               })

      assert connection.required_at
      assert Enforcement.mode(context.organization, connection) == :required
    end

    test "clears required_at on the way back down", context do
      link_identity(context, context.admin)

      {:ok, _connection} =
        configure(context, %{"enforcement_mode" => "required", "personal_keys" => "block"})

      assert {:ok, connection} = configure(context, %{"enforcement_mode" => "pilot"})

      refute connection.required_at
    end

    test "refuses a lifetime that is not on offer", context do
      assert {:error, changeset} = configure(context, %{"session_lifetime_seconds" => 60})
      assert errors_on(changeset).session_lifetime_seconds == "is invalid"
    end

    test "audits the change", context do
      link_identity(context, context.admin)

      {:ok, _connection} =
        configure(context, %{"enforcement_mode" => "required", "personal_keys" => "block"})

      log =
        Hexpm.Accounts.AuditLogs.all_by(context.admin)
        |> Enum.find(&(&1.action == "sso.enforcement.configure"))

      assert log.params["enforcement_mode"] == "required"
      assert log.params["personal_keys"] == "block"
    end

    test "refuses without a connection", %{admin: admin} do
      other = insert(:organization)
      insert(:organization_user, organization: other, user: admin, role: "admin")

      config = Application.fetch_env!(:hexpm, :organization_sso)

      Application.put_env(
        :hexpm,
        :organization_sso,
        Keyword.put(config, :beta_organizations, [other.name])
      )

      assert {:error, :not_configured} =
               SSO.configure_enforcement(other, %{"enforcement_mode" => "pilot"},
                 audit: audit_data(admin)
               )
    end
  end

  describe "set_member_enforcement/4" do
    test "records each state and audits it", context do
      for enforcement <- ["enforced", "exempt", nil] do
        assert {:ok, member} =
                 SSO.set_member_enforcement(context.organization, context.member, enforcement,
                   audit: audit_data(context.admin)
                 )

        assert member.sso_enforcement == enforcement
      end

      actions =
        Hexpm.Accounts.AuditLogs.all_by(context.admin)
        |> Enum.filter(&(&1.action == "sso.enforcement.member"))

      assert length(actions) == 3
    end

    test "treats a blank string as following the mode", context do
      assert {:ok, member} =
               SSO.set_member_enforcement(context.organization, context.member, "",
                 audit: audit_data(context.admin)
               )

      refute member.sso_enforcement
    end

    test "refuses anything else", context do
      assert {:error, changeset} =
               SSO.set_member_enforcement(context.organization, context.member, "maybe",
                 audit: audit_data(context.admin)
               )

      assert errors_on(changeset).sso_enforcement == "is invalid"
    end

    test "refuses a user who is not a member", context do
      assert {:error, :not_member} =
               SSO.set_member_enforcement(context.organization, insert(:user), "exempt",
                 audit: audit_data(context.admin)
               )
    end
  end

  defp configure(context, params) do
    SSO.configure_enforcement(context.organization, params, audit: audit_data(context.admin))
  end

  defp require_sso(context) do
    link_identity(context, context.admin)

    configure(context, %{"enforcement_mode" => "required", "personal_keys" => "block"})
  end

  defp link_identity(context, user) do
    insert(:organization_sso_identity,
      connection: context.connection,
      organization: context.organization,
      user: user
    )
  end

  defp browser_session(user) do
    insert(:session,
      user: user,
      expires_at: DateTime.add(DateTime.utc_now(), 30 * 24 * 60 * 60, :second)
    )
  end

  defp oauth_session(user) do
    insert(:session,
      user: user,
      type: "oauth",
      expires_at: DateTime.add(DateTime.utc_now(), 30 * 24 * 60 * 60, :second)
    )
  end

  defp token(session) do
    %Hexpm.OAuth.Token{user_session_id: session.id}
  end

  defp personal_key(user) do
    insert(:key, user: user, organization: nil)
  end

  defp authenticate(context, user, session) do
    identity =
      insert(:organization_sso_identity,
        connection: context.connection,
        organization: context.organization,
        user: user,
        subject: "sub-#{user.id}"
      )

    SSO.establish_org_session!(identity, session.id)
  end
end
