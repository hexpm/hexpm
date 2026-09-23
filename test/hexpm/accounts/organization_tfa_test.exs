defmodule Hexpm.Accounts.OrganizationTFATest do
  use Hexpm.DataCase
  import Hexpm.ConcurrencyCase

  alias Hexpm.Accounts.{
    OrganizationTFA,
    OrganizationAuth,
    Users,
    Organizations,
    OrganizationInvitations,
    OrganizationTFANotifications,
    OrganizationTFANotification
  }

  alias Hexpm.OAuth.Tokens
  alias Hexpm.UserSession

  setup do
    app_env(:hexpm, :organization_tfa, mode: :enabled, beta_organizations: [])
    :ok
  end

  defp context do
    admin = insert(:user_with_tfa)
    member = insert(:user)
    organization = insert(:organization, billing_seats: 10)
    insert(:organization_user, organization: organization, user: admin, role: "admin")
    insert(:organization_user, organization: organization, user: member, role: "read")
    session = browser(admin)
    %{organization: organization, admin: admin, member: member, session: session}
  end

  defp browser(user) do
    insert(:session, user: user, expires_at: DateTime.add(DateTime.utc_now(), 2_592_000))
  end

  defp configure(c, attrs) do
    OrganizationTFA.configure(c.organization, c.admin, c.session.id, attrs,
      audit: audit_data(c.admin)
    )
  end

  defp enroll(user) do
    secret = Hexpm.Accounts.TFA.generate_secret()

    {:ok, user} =
      Users.tfa_enable(user, secret, Hexpm.Accounts.TFA.time_based_token(secret),
        audit: audit_data(user)
      )

    user
  end

  test "rollout modes control new policies independently of SSO" do
    c = context()

    for {mode, names, enabled?, available?} <- [
          {:off, [c.organization.name], false, false},
          {:beta, [], false, false},
          {:beta, [c.organization.name <> "_other"], false, true},
          {:beta, [c.organization.name], true, true},
          {:enabled, [], true, true}
        ],
        sso_mode <- [:off, :enabled] do
      app_env(:hexpm, :organization_tfa, mode: mode, beta_organizations: names)
      app_env(:hexpm, :organization_sso, mode: sso_mode, beta_organizations: [])
      assert OrganizationTFA.enabled?(c.organization) == enabled?
      assert OrganizationTFA.available?() == available?
      assert OrganizationTFA.configurable?(c.organization) == enabled?

      attrs = %{"enforcement" => "transition", "grace_days" => "14"}

      if enabled? do
        assert {:ok, scheduled} = configure(c, attrs)
        assert OrganizationTFA.scheduled?(scheduled)
        assert {:ok, _} = configure(c, %{"enforcement" => "disabled"})
      else
        assert {:error, :unavailable} = configure(c, attrs)
        refute Repo.get!(Hexpm.Accounts.Organization, c.organization.id).tfa_required_at
      end
    end
  end

  test "an organization removed from the beta allowlist keeps enforcing and stays manageable" do
    for policy <- [
          %{"enforcement" => "immediate"},
          %{"enforcement" => "transition", "grace_days" => "14"}
        ] do
      app_env(:hexpm, :organization_tfa, mode: :enabled, beta_organizations: [])
      c = context()
      assert {:ok, organization} = configure(c, policy)
      app_env(:hexpm, :organization_tfa, mode: :beta, beta_organizations: ["other"])
      refute OrganizationTFA.enabled?(organization)
      assert OrganizationTFA.configurable?(organization)
      assert OrganizationTFA.enforced?(organization, organization.tfa_required_at)

      assert {:error, :tfa_enrollment_required} =
               Repo.transaction(fn -> OrganizationTFA.admit(organization, c.member) end)
               |> elem(1)

      if policy["enforcement"] == "immediate" do
        assert OrganizationAuth.check(organization, c.member) == {:error, :tfa_required}
      else
        assert OrganizationAuth.check(organization, c.member) == :ok
        assert {:ok, edited} = configure(c, %{"enforcement" => "transition", "grace_days" => "3"})
        assert DateTime.compare(edited.tfa_required_at, organization.tfa_required_at) == :lt
      end

      assert {:ok, disabled} = configure(c, %{"enforcement" => "disabled"})
      refute OrganizationTFA.scheduled?(disabled)
      refute OrganizationTFA.configurable?(disabled)
      assert OrganizationAuth.check(disabled, c.member) == :ok
      assert {:error, :unavailable} = configure(c, %{"enforcement" => "immediate"})
    end
  end

  test "the global switch off suspends enforcement while keeping policies and management" do
    app_env(:hexpm, :organization_tfa, mode: :enabled, beta_organizations: [])
    c = context()
    assert {:ok, organization} = configure(c, %{"enforcement" => "immediate"})
    assert OrganizationAuth.check(organization, c.member) == {:error, :tfa_required}

    app_env(:hexpm, :organization_tfa, mode: :off, beta_organizations: [])

    # The policy row is untouched, but nothing enforces.
    assert OrganizationTFA.scheduled?(organization)
    refute OrganizationTFA.active?(organization)
    refute OrganizationTFA.enforced?(organization, organization.tfa_required_at)
    assert OrganizationAuth.check(organization, c.member) == :ok
    assert OrganizationTFA.enrollment_status(organization, c.member) == "pending"

    assert :ok =
             Repo.transaction(fn -> OrganizationTFA.admit(organization, c.member) end) |> elem(1)

    assert OrganizationTFA.refused(c.member) == []
    assert OrganizationTFA.required_memberships(c.member) == []
    assert OrganizationAuth.required(c.member, [organization.name], nil) == []

    # It can still be managed while off, and flipping back resumes it unchanged.
    assert OrganizationTFA.configurable?(organization)
    app_env(:hexpm, :organization_tfa, mode: :enabled, beta_organizations: [])
    assert OrganizationTFA.enforced?(organization, organization.tfa_required_at)
    assert OrganizationAuth.check(organization, c.member) == {:error, :tfa_required}
  end

  test "existing organizations start disabled and all deadlines have exact boundaries" do
    c = context()
    assert c.organization.tfa_required_at == nil
    assert OrganizationAuth.check(c.organization, c.member) == :ok
    now = DateTime.utc_now()

    for seconds <- [0, 14 * 86_400, 30 * 86_400] do
      deadline = DateTime.add(now, seconds)
      assert OrganizationTFA.changeset(c.organization, %{tfa_required_at: deadline}, now).valid?
      organization = %{c.organization | tfa_required_at: deadline}
      refute OrganizationTFA.enforced?(organization, DateTime.add(deadline, -1, :microsecond))
      assert OrganizationTFA.enforced?(organization, deadline)
    end

    refute OrganizationTFA.changeset(
             c.organization,
             %{tfa_required_at: DateTime.add(now, 2_592_001)},
             now
           ).valid?
  end

  test "policy configuration requires an enrolled administrator" do
    c = context()
    attrs = %{"enforcement" => "transition", "grace_days" => "14"}

    assert {:error, :admin_required} =
             OrganizationTFA.configure(c.organization, c.member, c.session.id, attrs,
               audit: audit_data(c.member)
             )

    unenrolled = insert(:user)
    insert(:organization_user, organization: c.organization, user: unenrolled, role: "admin")

    assert {:error, :tfa_required} =
             OrganizationTFA.configure(c.organization, unenrolled, browser(unenrolled).id, attrs,
               audit: audit_data(unenrolled)
             )

    refute Repo.get!(Hexpm.Accounts.Organization, c.organization.id).tfa_required_at
    assert {:ok, org} = configure(c, attrs)
    assert org.tfa_policy_revision == 1
    assert DateTime.diff(org.tfa_required_at, DateTime.utc_now()) in 1_209_598..1_209_600
    assert OrganizationAuth.check(org, c.member) == :ok
    assert OrganizationTFA.enrollment_status(org, c.member) == "pending"
  end

  test "transition edits work; enforced policies must be disabled before a new transition" do
    c = context()
    assert {:ok, _} = configure(c, %{"enforcement" => "transition", "grace_days" => "14"})
    assert {:ok, _} = configure(c, %{"enforcement" => "transition", "grace_days" => "3"})
    assert {:ok, org} = configure(c, %{"enforcement" => "immediate"})

    assert {:error, %Ecto.Changeset{}} =
             configure(c, %{"enforcement" => "transition", "grace_days" => "14"})

    assert {:ok, kept} = configure(c, %{"enforcement" => "keep"})
    assert kept.tfa_required_at == org.tfa_required_at
    assert kept.tfa_policy_revision == org.tfa_policy_revision
    assert {:ok, disabled} = configure(c, %{"enforcement" => "disabled"})
    refute OrganizationTFA.scheduled?(disabled)
    assert {:ok, _} = configure(c, %{"enforcement" => "transition", "grace_days" => "14"})
  end

  test "suspension retains membership, role, ownership and seat and enrollment restores access" do
    c = context()
    before = Organizations.all_members(c.organization)
    assert {:ok, org} = configure(c, %{"enforcement" => "immediate"})
    assert OrganizationAuth.check(org, c.member) == {:error, :tfa_required}

    assert OrganizationAuth.check(org, c.member, insert(:key, user: c.member)) ==
             {:error, :tfa_required}

    assert OrganizationTFA.enrollment_status(org, c.member) == "overdue"
    assert Organizations.all_members(org) == before
    assert Hexpm.Accounts.Seats.used(org) == 2
    session = browser(c.member)
    user = enroll(c.member)
    assert OrganizationTFA.enrollment_status(org, user) == "enabled"
    assert OrganizationAuth.check(org, user) == :ok
    assert OrganizationAuth.check(org, user, nil, session.id) == :ok
    assert OrganizationAuth.check(org, user, insert(:key, user: user)) == :ok
    assert Organizations.all_members(org) == before
  end

  test "the account decides, so a stale struct is rechecked against the database" do
    c = context()
    {:ok, org} = configure(c, %{"enforcement" => "immediate"})
    enroll(c.member)
    assert OrganizationAuth.check(org, c.member) == :ok
    Repo.update!(Hexpm.Accounts.User.clear_tfa(c.admin))
    assert OrganizationAuth.check(org, c.admin) == {:error, :tfa_required}
  end

  test "enrollment is required for direct addition and an invitation remains pending" do
    c = context()
    user = insert(:user)
    {:ok, _} = configure(c, %{"enforcement" => "transition", "grace_days" => "14"})

    assert {:error, :tfa_enrollment_required} =
             Organizations.add_member(c.organization, user, %{"role" => "read"},
               audit: audit_data(c.admin)
             )

    {:ok, invitation} =
      OrganizationInvitations.invite(
        c.organization,
        %{"email" => hd(user.emails).email, "role" => "read"},
        c.admin,
        audit: audit_data(c.admin)
      )

    invitation = Repo.preload(invitation, :organization)

    assert {:error, :tfa_enrollment_required} =
             OrganizationInvitations.accept(invitation, user, audit: audit_data(user))

    assert Repo.get!(Hexpm.Accounts.OrganizationInvitation, invitation.id).accepted_at == nil
    assert Hexpm.Accounts.Seats.used(c.organization) == 2
    user = enroll(user)
    assert {:ok, _} = OrganizationInvitations.accept(invitation, user, audit: audit_data(user))
    assert Hexpm.Accounts.Seats.used(c.organization) == 3
  end

  test "transition blocks disabling 2FA and removal of the last eligible administrator" do
    c = context()

    {:ok, _} =
      Organizations.change_role(c.organization, c.member, %{"role" => "admin"},
        audit: audit_data(c.admin)
      )

    {:ok, _} = configure(c, %{"enforcement" => "transition", "grace_days" => "14"})

    assert {:error, :organization_tfa_required} =
             Users.tfa_disable(c.admin, audit: audit_data(c.admin))

    assert {:error, :last_admin} =
             Organizations.remove_member(c.organization, c.admin, audit: audit_data(c.admin))

    assert {:error, :last_admin} =
             Organizations.change_role(c.organization, c.admin, %{"role" => "read"},
               audit: audit_data(c.admin)
             )

    assert {:error, {:organizations, [_]}} = Users.delete(c.admin, audit: audit_data(c.admin))
  end

  test "replacing an authenticator keeps the member enrolled throughout" do
    c = context()
    {:ok, org} = configure(c, %{"enforcement" => "immediate"})
    secret = Hexpm.Accounts.TFA.generate_secret()
    assert :error = Users.tfa_enable(c.admin, secret, "invalid", audit: audit_data(c.admin))
    assert OrganizationAuth.check(org, c.admin) == :ok
    replaced = enroll(c.admin)
    assert replaced.tfa.secret != c.admin.tfa.secret
    assert OrganizationAuth.check(org, replaced) == :ok
  end

  test "unenrolled members are refused with every credential and organization credentials are exempt" do
    c = context()
    {:ok, org} = configure(c, %{"enforcement" => "immediate"})
    key = insert(:key, user: c.member)
    assert OrganizationAuth.check(org, c.member, key) == {:error, :tfa_required}

    token = %Hexpm.OAuth.Token{
      grant_type: "client_credentials",
      user_id: c.member.id,
      user_session_id: browser(c.member).id
    }

    assert OrganizationAuth.check(org, c.member, token) == {:error, :tfa_required}
    assert OrganizationAuth.check(org, c.member) == {:error, :tfa_required}
    assert OrganizationAuth.check(org, c.admin, insert(:key, user: c.admin)) == :ok
    assert OrganizationAuth.check(org, org, key) == :ok
    assert OrganizationAuth.check(insert(:organization), c.member, key) == :ok

    assert [{refused, :tfa_required}] = OrganizationAuth.personal_key_refusals(c.member)
    assert refused.id == org.id
    assert OrganizationAuth.personal_key_refusals(c.admin) == []

    assert {:error, :key, changeset, _} =
             Hexpm.Accounts.Keys.create(
               c.member,
               %{name: "refused", permissions: [%{domain: "repository", resource: org.name}]},
               audit: audit_data(c.member)
             )

    assert [%Ecto.Changeset{errors: [resource: {message, _}]}] = changeset.changes.permissions
    assert message =~ "two-factor authentication"
  end

  test "notifications are durable per revision and obsolete queued notices are cancelled" do
    c = context()
    {:ok, org} = configure(c, %{"enforcement" => "transition", "grace_days" => "14"})
    assert Repo.aggregate(OrganizationTFANotification, :count) == 1
    OrganizationTFANotifications.sweep()
    OrganizationTFANotifications.sweep()
    assert Repo.aggregate(OrganizationTFANotification, :count) == 1
    {:ok, _} = configure(c, %{"enforcement" => "disabled"})

    refute Repo.exists?(
             from(e in Hexpm.Emails.OutboxEntry,
               where: e.scope_key == ^"tfa:organization:#{org.id}"
             )
           )

    assert Repo.aggregate(OrganizationTFANotification, :count) == 1
  end

  test "a transition notifies only unenrolled members and enrolling cancels the notice" do
    c = context()
    {:ok, org} = configure(c, %{"enforcement" => "transition", "grace_days" => "14"})

    assert Repo.all(
             from(n in OrganizationTFANotification,
               where: n.stage == "scheduled",
               select: n.user_id
             )
           ) == [c.member.id]

    scheduled =
      from(e in Hexpm.Emails.OutboxEntry,
        where: like(e.group_key, ^"tfa:#{org.id}:%:%:scheduled"),
        select: e.group_key
      )

    assert Repo.all(scheduled) == [
             "tfa:#{org.id}:#{org.tfa_policy_revision}:#{c.member.id}:scheduled"
           ]

    enroll(c.member)

    assert Repo.all(scheduled) == []
  end

  test "a reminder is only sent when the transition is longer than its window" do
    for {days, stage} <- [{7, "seven_days"}, {1, "one_day"}] do
      c = context()

      {:ok, org} =
        configure(c, %{"enforcement" => "transition", "grace_days" => Integer.to_string(days)})

      OrganizationTFANotifications.sweep()

      refute Repo.exists?(
               from(n in OrganizationTFANotification,
                 where: n.organization_id == ^org.id and n.stage == ^stage
               )
             )
    end

    c = context()
    {:ok, org} = configure(c, %{"enforcement" => "transition", "grace_days" => "8"})
    OrganizationTFANotifications.sweep(DateTime.add(org.tfa_required_at, -7 * 86_400))

    assert Repo.all(
             from(n in OrganizationTFANotification,
               where: n.organization_id == ^org.id and n.stage == "seven_days",
               select: n.user_id
             )
           ) == [c.member.id]
  end

  test "immediate enforcement sends no scheduled notice and suspends only unenrolled members" do
    c = context()
    {:ok, _} = configure(c, %{"enforcement" => "immediate"})

    refute Repo.exists?(from(n in OrganizationTFANotification, where: n.stage == "scheduled"))

    OrganizationTFANotifications.sweep()

    assert Repo.all(
             from(n in OrganizationTFANotification,
               where: n.stage == "suspended",
               select: n.user_id
             )
           ) == [c.member.id]
  end

  test "policy activation and disabling its administrator's 2FA serialize on separate connections" do
    committed(&context/0, fn c ->
      results =
        race([
          fn -> configure(c, %{"enforcement" => "immediate"}) end,
          fn -> Users.tfa_disable(c.admin, audit: audit_data(c.admin)) end
        ])

      organization = Repo.get!(Hexpm.Accounts.Organization, c.organization.id)
      user = Repo.get!(Hexpm.Accounts.User, c.admin.id)

      assert not OrganizationTFA.scheduled?(organization) or
               Hexpm.Accounts.User.tfa_enabled?(user)

      assert Enum.any?(results, &match?({:error, _}, &1))
    end)
  end

  test "SSO and 2FA requirements are tracked independently, including SSO exemptions" do
    c = context()
    config = Application.fetch_env!(:hexpm, :organization_sso)
    Application.put_env(:hexpm, :organization_sso, Keyword.merge(config, mode: :enabled))
    on_exit(fn -> Application.put_env(:hexpm, :organization_sso, config) end)
    {:ok, org} = configure(c, %{"enforcement" => "immediate"})

    connection =
      insert(:organization_sso_connection,
        organization: org,
        tested_at: DateTime.utc_now(),
        enabled_at: DateTime.utc_now(),
        enforcement_mode: "required",
        required_at: DateTime.add(DateTime.utc_now(), -1),
        personal_keys: "allow"
      )

    identity =
      insert(:organization_sso_identity,
        organization: org,
        connection: connection,
        user: c.member
      )

    client = insert(:oauth_client)
    target = insert(:oauth_session, user: c.member, client_id: client.client_id)

    assert OrganizationAuth.required(c.member, [org.name], target.id) == [
             %{organization: org.name, requirements: ["tfa", "sso"]}
           ]

    sso = Hexpm.Accounts.SSO.establish_org_session!(identity, target.id)

    assert OrganizationAuth.required(c.member, [org.name], target.id) == [
             %{organization: org.name, requirements: ["tfa"]}
           ]

    user = enroll(c.member)
    assert OrganizationAuth.required(user, [org.name], target.id) == []

    Repo.update_all(from(s in Hexpm.Accounts.SSO.OrgSession, where: s.id == ^sso.id),
      set: [expires_at: DateTime.utc_now()]
    )

    assert OrganizationAuth.required(user, [org.name], target.id) == [
             %{organization: org.name, requirements: ["sso"]}
           ]

    Hexpm.Accounts.SSO.establish_org_session!(identity, target.id)
    assert OrganizationAuth.required(user, [org.name], target.id) == []

    Repo.update_all(
      from(m in Hexpm.Accounts.OrganizationUser, where: m.organization_id == ^org.id),
      set: [sso_enforcement: "exempt"]
    )

    assert OrganizationAuth.required(user, [org.name], browser(user).id) == []
    assert OrganizationAuth.check(org, user, insert(:key, user: user)) == :ok
    assert OrganizationAuth.check(org, c.member, insert(:key, user: user)) == :ok

    {:ok, _} = configure(c, %{"enforcement" => "disabled"})
    assert OrganizationAuth.required(user, [org.name], target.id) == []
    assert Repo.get!(Hexpm.Accounts.SSO.Connection, connection.id).enforcement_mode == "required"
  end

  test "all grant types filter 2FA scopes and preserve unrelated organization access" do
    c = context()
    {:ok, org} = configure(c, %{"enforcement" => "immediate"})
    other = insert(:organization)
    insert(:organization_user, organization: other, user: c.member, role: "read")
    client = insert(:oauth_client)
    session = browser(c.member)

    for grant <- [
          "authorization_code",
          "urn:ietf:params:oauth:grant-type:device_code",
          "refresh_token",
          "client_credentials"
        ] do
      opts = if grant == "client_credentials", do: [credential: %Hexpm.Accounts.Key{}], else: []

      token =
        Tokens.create_for_user(
          c.member,
          client.client_id,
          ["api:read", "repository:#{org.name}", "docs:#{org.name}", "repository:#{other.name}"],
          grant,
          nil,
          opts
        )
        |> Ecto.Changeset.apply_changes()

      assert token.scopes == ["api:read", "repository:#{other.name}"]

      if grant == "client_credentials",
        do: assert(token.organization_reauth_required == []),
        else:
          assert(
            token.organization_reauth_required == [
              %{organization: org.name, requirements: ["tfa"]}
            ]
          )
    end

    token =
      Tokens.create_for_user(
        c.member,
        client.client_id,
        ["repository:#{org.name}"],
        "client_credentials",
        nil,
        credential: %Hexpm.Accounts.Key{},
        user_session_id: session.id
      )
      |> Ecto.Changeset.apply_changes()

    assert token.scopes == []
    assert token.refresh_token == nil

    enrolled =
      Tokens.create_for_user(
        c.admin,
        client.client_id,
        ["api:read", "repository:#{org.name}"],
        "authorization_code",
        nil,
        user_session_id: c.session.id
      )
      |> Ecto.Changeset.apply_changes()

    assert enrolled.scopes == ["api:read", "repository:#{org.name}"]
    assert enrolled.organization_reauth_required == []
  end

  test "reminders skip elapsed stages and suspension notices are deduplicated after the deadline" do
    c = context()
    {:ok, org} = configure(c, %{"enforcement" => "transition", "grace_days" => "14"})
    now = DateTime.utc_now()

    Repo.update_all(from(o in Hexpm.Accounts.Organization, where: o.id == ^org.id),
      set: [
        tfa_required_at: DateTime.add(now, 6 * 86_400),
        tfa_policy_updated_at: DateTime.add(now, -8 * 86_400)
      ]
    )

    OrganizationTFANotifications.sweep()
    OrganizationTFANotifications.sweep()

    assert Repo.aggregate(
             from(n in OrganizationTFANotification, where: n.stage == "seven_days"),
             :count
           ) == 1

    Repo.update_all(from(o in Hexpm.Accounts.Organization, where: o.id == ^org.id),
      set: [tfa_required_at: DateTime.add(now, 86_399)]
    )

    OrganizationTFANotifications.sweep()

    assert Repo.aggregate(
             from(n in OrganizationTFANotification, where: n.stage == "one_day"),
             :count
           ) == 1

    enroll(c.member)

    refute Repo.exists?(
             from(e in Hexpm.Emails.OutboxEntry,
               where: like(e.group_key, ^"tfa:#{org.id}:%:#{c.member.id}:one_day")
             )
           )

    Repo.update_all(from(o in Hexpm.Accounts.Organization, where: o.id == ^org.id),
      set: [tfa_required_at: DateTime.add(now, -1)]
    )

    OrganizationTFANotifications.sweep()
    OrganizationTFANotifications.sweep()

    assert Repo.aggregate(
             from(n in OrganizationTFANotification, where: n.stage == "summary"),
             :count
           ) == 1

    assert Repo.aggregate(
             from(n in OrganizationTFANotification, where: n.stage == "suspended"),
             :count
           ) == 0
  end

  test "concurrent administrator removals preserve an enrolled administrator" do
    committed(
      fn ->
        c = context()
        other = insert(:user_with_tfa)
        insert(:organization_user, organization: c.organization, user: other, role: "admin")
        {:ok, org} = configure(c, %{"enforcement" => "immediate"})
        Map.merge(c, %{organization: org, other: other})
      end,
      fn c ->
        results =
          race([c.admin, c.other], fn user ->
            Organizations.remove_member(c.organization, user, audit: audit_data(user))
          end)

        assert Enum.count(results, &(&1 == :ok)) == 1
        assert Enum.count(results, &(&1 == {:error, :last_admin})) == 1

        assert Enum.any?(
                 Organizations.all_members(c.organization),
                 &OrganizationTFA.eligible_admin?(c.organization, &1)
               )
      end
    )
  end

  test "admission racing with enrollment rechecks the locked account" do
    committed(&context/0, fn c ->
      {:ok, _} = configure(c, %{"enforcement" => "transition", "grace_days" => "14"})
      user = insert(:user)
      secret = Hexpm.Accounts.TFA.generate_secret()

      [admitted, enrolled] =
        race([
          fn ->
            Organizations.add_member(c.organization, user, %{"role" => "read"},
              audit: audit_data(c.admin)
            )
          end,
          fn ->
            Users.tfa_enable(user, secret, Hexpm.Accounts.TFA.time_based_token(secret),
              audit: audit_data(user)
            )
          end
        ])

      assert {:ok, _} = enrolled
      assert match?({:ok, _}, admitted) or admitted == {:error, :tfa_enrollment_required}

      if Organizations.get_role(c.organization, user),
        do: assert(Hexpm.Accounts.User.tfa_enabled?(Repo.get!(Hexpm.Accounts.User, user.id)))
    end)
  end

  test "suspension notices begin at the exact deadline and enrolled members get no reminders" do
    c = context()
    insert(:key, user: c.admin, permissions: [build(:key_permission, domain: "api")])
    {:ok, org} = configure(c, %{"enforcement" => "transition", "grace_days" => "14"})
    OrganizationTFANotifications.sweep(DateTime.add(org.tfa_required_at, -7 * 86_400))

    assert Repo.all(
             from(n in OrganizationTFANotification,
               where: n.stage == "seven_days",
               select: n.user_id
             )
           ) == [c.member.id]

    OrganizationTFANotifications.sweep(DateTime.add(org.tfa_required_at, -1, :microsecond))

    refute Repo.exists?(
             from(n in OrganizationTFANotification, where: n.stage in ["suspended", "summary"])
           )

    OrganizationTFANotifications.sweep(org.tfa_required_at)
    OrganizationTFANotifications.sweep(org.tfa_required_at)

    assert Repo.aggregate(
             from(n in OrganizationTFANotification, where: n.stage == "suspended"),
             :count
           ) == 1

    assert Repo.aggregate(
             from(n in OrganizationTFANotification, where: n.stage == "summary"),
             :count
           ) == 1
  end

  test "invitation acceptance rechecks available seats after enrollment" do
    c = context()
    {:ok, org} = configure(c, %{"enforcement" => "transition", "grace_days" => "14"})

    org =
      org |> Ecto.Changeset.change(billing_seats: 3, billing_override: false) |> Repo.update!()

    user = insert(:user)

    {:ok, invitation} =
      OrganizationInvitations.invite(
        org,
        %{"email" => hd(user.emails).email, "role" => "read"},
        c.admin,
        audit: audit_data(c.admin)
      )

    assert {:error, :tfa_enrollment_required} =
             OrganizationInvitations.accept(invitation, user, audit: audit_data(user))

    assert {:ok, _} =
             Organizations.add_member(org, insert(:user_with_tfa), %{"role" => "read"},
               audit: audit_data(c.admin)
             )

    user = enroll(user)

    assert {:error, :seats_exhausted} =
             OrganizationInvitations.accept(invitation, user, audit: audit_data(user))

    refute Repo.get!(Hexpm.Accounts.OrganizationInvitation, invitation.id).accepted_at
    refute Organizations.get_role(org, user)
    assert Hexpm.Accounts.Seats.used(org) == 3
  end

  test "recovery-code rotation with a stale user doesn't restore a replaced authenticator" do
    c = context()
    replaced = enroll(c.admin)
    rotated = Users.tfa_rotate_recovery_codes(c.admin, audit: audit_data(c.admin))
    assert rotated.tfa.secret == replaced.tfa.secret
    refute rotated.tfa.recovery_codes == replaced.tfa.recovery_codes

    assert {:error, :not_enrolled} =
             Users.tfa_rotate_recovery_codes(c.member, audit: audit_data(c.member))
  end

  test "membership removal invalidates an open browser authorization" do
    c = context()
    {:ok, org} = configure(c, %{"enforcement" => "immediate"})
    target = insert(:oauth_session, user: c.member, client_id: insert(:oauth_client).client_id)

    {:ok, authorization} =
      Hexpm.Accounts.SSO.request_authorization(c.member, target.id, [org.name])

    assert [{%{id: id}, ["tfa"]}] = Hexpm.Accounts.SSO.authorization_status(authorization)
    assert id == org.id

    Repo.delete_all(
      from(m in Hexpm.Accounts.OrganizationUser,
        where: m.organization_id == ^org.id and m.user_id == ^c.member.id
      )
    )

    assert Hexpm.Accounts.SSO.authorization_status(authorization) == []
  end

  test "an authorization tracks enrollment and the target session's SSO access separately" do
    c = context()
    {:ok, org} = configure(c, %{"enforcement" => "immediate"})
    config = Application.fetch_env!(:hexpm, :organization_sso)
    Application.put_env(:hexpm, :organization_sso, Keyword.put(config, :mode, :enabled))
    on_exit(fn -> Application.put_env(:hexpm, :organization_sso, config) end)

    connection =
      insert(:organization_sso_connection,
        organization: org,
        tested_at: DateTime.utc_now(),
        enabled_at: DateTime.utc_now(),
        enforcement_mode: "required",
        required_at: DateTime.add(DateTime.utc_now(), -1)
      )

    identity =
      insert(:organization_sso_identity,
        organization: org,
        connection: connection,
        user: c.member
      )

    target = insert(:oauth_session, user: c.member, client_id: insert(:oauth_client).client_id)

    {:ok, authorization} =
      Hexpm.Accounts.SSO.request_authorization(c.member, target.id, [org.name])

    assert [{_, ["tfa", "sso"]}] = Hexpm.Accounts.SSO.authorization_status(authorization)
    Hexpm.Accounts.SSO.establish_org_session!(identity, target.id)
    assert [{_, ["tfa"]}] = Hexpm.Accounts.SSO.authorization_status(authorization)
    enroll(c.member)
    assert [{_, []}] = Hexpm.Accounts.SSO.authorization_status(authorization)
    assert Repo.get!(UserSession, target.id).expires_at == target.expires_at
  end

  test "queued administrator summaries reflect enrollment and membership removal" do
    c = context()
    {:ok, organization} = configure(c, %{"enforcement" => "immediate"})
    OrganizationTFANotifications.sweep()

    summary =
      Repo.one!(
        from(e in Hexpm.Emails.OutboxEntry,
          where: e.group_key == ^"tfa:#{organization.id}:1:#{c.admin.id}:summary"
        )
      )

    assert summary.email["text_body"] =~ c.member.username
    enroll(c.member)
    updated = Repo.get!(Hexpm.Emails.OutboxEntry, summary.id)
    assert updated.email["text_body"] =~ "Every member has 2FA enabled, so no one is suspended."
    refute updated.email["text_body"] =~ c.member.username

    assert Repo.aggregate(
             from(n in OrganizationTFANotification, where: n.stage == "summary"),
             :count
           ) == 1

    other = insert(:user)
    insert(:organization_user, user: other, organization: organization, role: "read")
    OrganizationTFANotifications.prepare_delivery!(updated)
    assert Repo.get!(Hexpm.Emails.OutboxEntry, summary.id).email["text_body"] =~ other.username
    assert :ok = Organizations.remove_member(organization, other, audit: audit_data(c.admin))
    refute Repo.get!(Hexpm.Emails.OutboxEntry, summary.id).email["text_body"] =~ other.username
    OrganizationTFANotifications.sweep()

    assert Repo.aggregate(
             from(n in OrganizationTFANotification, where: n.stage == "summary"),
             :count
           ) == 1
  end

  test "delivery refreshes a stale queued summary without sending it twice" do
    c = context()
    {:ok, organization} = configure(c, %{"enforcement" => "immediate"})
    OrganizationTFANotifications.sweep()

    summary =
      Repo.one!(
        from(e in Hexpm.Emails.OutboxEntry,
          where: e.group_key == ^"tfa:#{organization.id}:1:#{c.admin.id}:summary"
        )
      )

    enroll(c.member)

    Repo.update_all(from(e in Hexpm.Emails.OutboxEntry, where: e.id == ^summary.id),
      set: [email: summary.email]
    )

    job = %Oban.Job{args: %{"outbox_entry_id" => summary.id}, attempt: 1, max_attempts: 10}
    assert :ok = Hexpm.Emails.OutboxWorker.perform(job)
    delivered = Repo.get!(Hexpm.Emails.OutboxEntry, summary.id)
    assert delivered.delivered_at
    assert delivered.email["text_body"] =~ "Every member has 2FA enabled, so no one is suspended."
    refute delivered.email["text_body"] =~ c.member.username
    assert :ok = Hexpm.Emails.OutboxWorker.perform(job)
    assert Repo.get!(Hexpm.Emails.OutboxEntry, summary.id).delivered_at == delivered.delivered_at
  end
end
