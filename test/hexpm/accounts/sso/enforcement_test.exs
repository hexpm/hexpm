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

    test "tells an OAuth token to authenticate the session it is on", context do
      session = oauth_session(context.member)
      message = Enforcement.refusal_message(:sso_required, context.organization, token(session))

      assert message =~ "requires authenticating through its identity provider"
      assert message =~ "mix hex.user auth"

      # A sign-in URL would authenticate whichever browser session followed it,
      # which is not the one the token is on.
      refute message =~ "/sso/org/"

      # The client only prompts for the organizations the project depends on, so
      # a project that publishes here and depends on nothing here is told to run
      # something that would do nothing.
      refute message =~ "deps.get"
    end

    test "tells a username and password that it cannot hold the session", context do
      message = Enforcement.refusal_message(:sso_required, context.organization)

      assert message =~ "requires authenticating through its identity provider"
      assert message =~ "username and password"
      assert message =~ "mix hex.user auth"
      refute message =~ "/sso/org/"
    end

    test "treats a token exchanged from a personal key as that key", context do
      {:ok, _connection} = require_sso(context)
      session = oauth_session(context.member)

      assert Enforcement.check(
               context.organization,
               context.member,
               api_key_token(session),
               session.id
             ) == {:error, :personal_key}
    end

    test "lets that token through where the organization allows personal keys", context do
      link_identity(context, context.admin)

      {:ok, _connection} =
        configure(context, %{"enforcement_mode" => "required", "personal_keys" => "allow"})

      session = oauth_session(context.member)

      assert Enforcement.check(
               context.organization,
               context.member,
               api_key_token(session),
               session.id
             ) == :ok
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
    test "audits every reach and mails the administrators once an hour", context do
      {:ok, _connection} = require_sso(context)

      for screen <- [:billing, :sso, :add_seats] do
        Enforcement.break_glass(
          context.organization,
          context.member,
          screen,
          audit_data(context.member)
        )
      end

      logs =
        Hexpm.Accounts.AuditLogs.all_by(context.organization)
        |> Enum.filter(&(&1.action == "sso.break_glass"))

      # Each entry names its own screen. Keeping only the first would leave the
      # later actions indistinguishable from an administrator with a session.
      assert length(logs) == 3
      assert Enum.map(logs, & &1.params["screen"]) |> Enum.sort() == ~w(add_seats billing sso)

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
    test "requires SSO without saying anything about personal keys", context do
      link_identity(context, context.admin)

      assert {:ok, connection} = configure(context, %{"enforcement_mode" => "required"})
      assert connection.enforcement_mode == "required"
      assert is_nil(connection.personal_keys)
      refute SSO.Connection.blocks_personal_keys?(connection)
    end

    test "leaves personal keys alone for a required organization that said nothing", context do
      link_identity(context, context.admin)

      key =
        insert(:key,
          user: context.member,
          organization: nil,
          permissions: [
            build(:key_permission, domain: "repository", resource: context.organization.name)
          ]
        )

      {:ok, _connection} =
        configure(context, %{
          "enforcement_mode" => "required",
          "required_at" => DateTime.add(DateTime.utc_now(), -60, :second)
        })

      assert Enforcement.personal_key_refused(context.member) == []
      assert Enforcement.sweep_personal_keys() == 0
      assert Repo.get!(Hexpm.Accounts.Key, key.id).permissions == key.permissions
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

    test "refuses a required-by date it cannot read", context do
      link_identity(context, context.admin)

      assert {:error, changeset} =
               configure(context, %{
                 "enforcement_mode" => "required",
                 "personal_keys" => "block",
                 "required_at" => "01/09/2026"
               })

      assert errors_on(changeset).required_at =~ "expected type utc_datetime"
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

    test "refuses someone who is not an administrator", context do
      assert {:error, :admin_required} =
               SSO.set_member_enforcement(context.organization, context.member, "exempt",
                 audit: audit_data(context.member)
               )

      refute Repo.get_by!(Hexpm.Accounts.OrganizationUser,
               organization_id: context.organization.id,
               user_id: context.member.id
             ).sso_enforcement
    end

    test "refuses to enforce the last administrator who can still get in", context do
      {:ok, _member} =
        SSO.set_member_enforcement(context.organization, context.admin, "exempt",
          audit: audit_data(context.admin)
        )

      {:ok, _connection} =
        configure(context, %{"enforcement_mode" => "required", "personal_keys" => "block"})

      assert {:error, :no_reachable_admin} =
               SSO.set_member_enforcement(context.organization, context.admin, "enforced",
                 audit: audit_data(context.admin)
               )

      assert Repo.get_by!(Hexpm.Accounts.OrganizationUser,
               organization_id: context.organization.id,
               user_id: context.admin.id
             ).sso_enforcement == "exempt"
    end

    test "allows it while another administrator is still reachable", context do
      other_admin = insert(:user)

      insert(:organization_user,
        organization: context.organization,
        user: other_admin,
        role: "admin"
      )

      link_identity(context, other_admin)

      {:ok, _member} =
        SSO.set_member_enforcement(context.organization, context.admin, "exempt",
          audit: audit_data(context.admin)
        )

      {:ok, _connection} =
        configure(context, %{"enforcement_mode" => "required", "personal_keys" => "block"})

      assert {:ok, member} =
               SSO.set_member_enforcement(context.organization, context.admin, "enforced",
                 audit: audit_data(context.admin)
               )

      assert member.sso_enforcement == "enforced"
    end

    test "does not hold an organization that has no reachable administrator to it", context do
      link_identity(context, context.admin)

      {:ok, _connection} =
        configure(context, %{"enforcement_mode" => "required", "personal_keys" => "block"})

      Repo.delete_all(Hexpm.Accounts.SSO.Identity)

      # Nothing here would make it worse, and the change that gives the
      # organization an administrator back goes through the same function.
      assert {:ok, member} =
               SSO.set_member_enforcement(context.organization, context.member, "enforced",
                 audit: audit_data(context.admin)
               )

      assert member.sso_enforcement == "enforced"
    end
  end

  describe "a pilot that blocks personal keys" do
    test "turns away the members it pilots", context do
      link_identity(context, context.admin)

      {:ok, _connection} =
        configure(context, %{"enforcement_mode" => "pilot", "personal_keys" => "block"})

      {:ok, _member} =
        SSO.set_member_enforcement(context.organization, context.member, "enforced",
          audit: audit_data(context.admin)
        )

      assert Enforcement.check(
               context.organization,
               context.member,
               personal_key(context.member)
             ) ==
               {:error, :personal_key}

      assert Enforcement.personal_key_refused(context.member) != []
    end

    test "leaves the members it does not", context do
      link_identity(context, context.admin)

      {:ok, _connection} =
        configure(context, %{"enforcement_mode" => "pilot", "personal_keys" => "block"})

      assert Enforcement.check(
               context.organization,
               context.member,
               personal_key(context.member)
             ) == :ok

      assert Enforcement.personal_key_refused(context.member) == []
    end
  end

  describe "a subscription that has lapsed" do
    test "does not turn enforcement off", context do
      {:ok, connection} = require_sso(context)
      organization = lapse_billing(context)

      refute Hexpm.Accounts.SSO.Features.enabled?(organization)
      assert Enforcement.mode(organization, connection) == :required
      assert Enforcement.check(organization, context.member) == {:error, :sso_required}
    end

    test "still lets the organization turn it off", context do
      {:ok, _connection} = require_sso(context)
      organization = lapse_billing(context)

      assert {:ok, connection} =
               Hexpm.Accounts.SSO.configure_enforcement(
                 organization,
                 %{"enforcement_mode" => "optional"},
                 audit: audit_data(context.admin)
               )

      assert Enforcement.mode(organization, connection) == :optional
    end

    test "still lets the organization disable and delete the connection", context do
      {:ok, _connection} = require_sso(context)
      organization = lapse_billing(context)

      assert {:ok, _connection} =
               Hexpm.Accounts.SSO.disable(organization, audit: audit_data(context.admin))

      assert {:ok, _connection} =
               Hexpm.Accounts.SSO.delete_connection(organization,
                 audit: audit_data(context.admin)
               )
    end
  end

  describe "a required-by date that has not passed" do
    test "names the keys the date will turn away, not only the ones already refused", context do
      link_identity(context, context.admin)

      {:ok, connection} =
        configure(context, %{
          "enforcement_mode" => "required",
          "personal_keys" => "block",
          "required_at" => Date.utc_today() |> Date.add(9) |> Date.to_iso8601()
        })

      follows_mode = insert(:user)
      insert(:organization_user, organization: context.organization, user: follows_mode)

      key =
        insert(:key,
          user: follows_mode,
          organization: nil,
          permissions: [
            build(:key_permission, domain: "repository", resource: context.organization.name)
          ]
        )

      # Governed by the mode rather than by a per-member flag, so nothing turns
      # them away yet and the sweep will on the date.
      assert Enforcement.blocked_personal_keys(context.organization, connection) == []
      assert [pending] = Enforcement.pending_personal_keys(context.organization, connection)
      assert pending.id == key.id
    end

    test "is empty once the date has passed", context do
      {:ok, connection} = require_sso(context)

      assert Enforcement.pending_personal_keys(context.organization, connection) == []
    end
  end

  defp lapse_billing(context) do
    config = Application.fetch_env!(:hexpm, :organization_sso)

    Application.put_env(
      :hexpm,
      :organization_sso,
      Keyword.merge(config, mode: :enabled, all_organizations: false)
    )

    Repo.update_all(
      from(o in Hexpm.Accounts.Organization, where: o.id == ^context.organization.id),
      set: [billing_active: false]
    )

    Repo.get!(Hexpm.Accounts.Organization, context.organization.id)
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

  defp api_key_token(session) do
    %Hexpm.OAuth.Token{
      user_session_id: session.id,
      user_id: session.user_id,
      grant_type: "client_credentials"
    }
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
