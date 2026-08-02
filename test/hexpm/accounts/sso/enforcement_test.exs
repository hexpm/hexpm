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

  describe "blocked_organization_ids/2" do
    test "is empty for a member of an optional organization", context do
      session = browser_session(context.member)

      assert Enforcement.blocked_organization_ids(context.member, session.id)
             |> Enum.empty?()
    end

    test "names an organization a governed member has not authenticated for", context do
      {:ok, _connection} = require_sso(context)
      session = browser_session(context.member)

      assert Enforcement.blocked_organization_ids(context.member, session.id) ==
               MapSet.new([context.organization.id])
    end

    test "is empty once the member has a current session for it", context do
      {:ok, _connection} = require_sso(context)
      session = browser_session(context.member)
      authenticate(context, context.member, session)

      assert Enforcement.blocked_organization_ids(context.member, session.id)
             |> Enum.empty?()
    end

    test "is per browser session, not per account", context do
      {:ok, _connection} = require_sso(context)
      authenticated = browser_session(context.member)
      other = browser_session(context.member)
      authenticate(context, context.member, authenticated)

      assert Enforcement.blocked_organization_ids(context.member, authenticated.id)
             |> Enum.empty?()

      assert Enforcement.blocked_organization_ids(context.member, other.id) ==
               MapSet.new([context.organization.id])
    end

    test "treats an expired session as no session", context do
      {:ok, _connection} = require_sso(context)
      session = browser_session(context.member)
      org_session = authenticate(context, context.member, session)

      org_session
      |> Ecto.Changeset.change(expires_at: DateTime.add(DateTime.utc_now(), -1, :second))
      |> Repo.update!()

      assert Enforcement.blocked_organization_ids(context.member, session.id) ==
               MapSet.new([context.organization.id])
    end

    test "blocks everything governed when there is no session to check", context do
      {:ok, _connection} = require_sso(context)

      # A static credential cannot hold an organization access session, so every
      # governed organization is out of reach for it.
      assert Enforcement.blocked_organization_ids(context.member, nil) ==
               MapSet.new([context.organization.id])
    end

    test "skips an exempt member", context do
      {:ok, _connection} = require_sso(context)

      {:ok, _member} =
        SSO.set_member_enforcement(context.organization, context.member, "exempt",
          audit: audit_data(context.admin)
        )

      session = browser_session(context.member)

      assert Enforcement.blocked_organization_ids(context.member, session.id)
             |> Enum.empty?()
    end

    test "is empty for a user with no organizations" do
      user = insert(:user)
      session = browser_session(user)

      assert Enforcement.blocked_organization_ids(user, session.id) |> Enum.empty?()
    end

    test "is empty for nobody" do
      assert Enforcement.blocked_organization_ids(nil, nil) |> Enum.empty?()
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
