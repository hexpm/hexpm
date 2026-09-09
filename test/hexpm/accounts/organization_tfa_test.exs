defmodule Hexpm.Accounts.OrganizationTFATest do
  use Hexpm.DataCase
  import Hexpm.ConcurrencyCase

  alias Hexpm.Accounts.{
    OrganizationTFA,
    OrganizationAuth,
    TFASessions,
    Users,
    Organizations,
    OrganizationInvitations,
    OrganizationTFANotifications,
    OrganizationTFANotification
  }

  alias Hexpm.OAuth.{Tokens, JWT}
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
    {:ok, :ok} = TFASessions.record_verified!(admin, session.id)
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

  test "existing policies remain enforced and manageable after leaving the rollout" do
    for rollout <- [
          [mode: :off, beta_organizations: []],
          [mode: :beta, beta_organizations: ["other"]]
        ],
        policy <- [
          %{"enforcement" => "immediate"},
          %{"enforcement" => "transition", "grace_days" => "14"}
        ] do
      app_env(:hexpm, :organization_tfa, mode: :enabled, beta_organizations: [])
      c = context()
      assert {:ok, organization} = configure(c, policy)
      app_env(:hexpm, :organization_tfa, rollout)
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

      assert {:ok, changed} = configure(c, %{"tfa_session_lifetime_seconds" => "86400"})
      assert changed.tfa_session_lifetime_seconds == 86400
      assert {:ok, disabled} = configure(c, %{"enforcement" => "disabled"})
      refute OrganizationTFA.scheduled?(disabled)
      refute OrganizationTFA.configurable?(disabled)
      assert OrganizationAuth.check(disabled, c.member) == :ok
      assert {:error, :unavailable} = configure(c, %{"enforcement" => "immediate"})
    end
  end

  test "existing organizations start disabled and all deadlines have exact boundaries" do
    c = context()
    assert c.organization.tfa_required_at == nil
    assert c.organization.tfa_session_lifetime_seconds == 604_800
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

  test "policy configuration requires an enrolled administrator with fresh proof" do
    c = context()
    attrs = %{"enforcement" => "transition", "grace_days" => "14"}

    assert {:error, :admin_required} =
             OrganizationTFA.configure(c.organization, c.member, c.session.id, attrs,
               audit: audit_data(c.member)
             )

    unverified = browser(c.admin)

    assert {:error, :tfa_required} =
             OrganizationTFA.configure(c.organization, c.admin, unverified.id, attrs,
               audit: audit_data(c.admin)
             )

    Repo.update_all(from(s in UserSession, where: s.id == ^c.session.id),
      set: [tfa_verified_at: DateTime.add(DateTime.utc_now(), -301)]
    )

    assert {:error, :tfa_required} = configure(c, attrs)
    {:ok, :ok} = TFASessions.record_verified!(c.admin, c.session.id)
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

    assert {:ok, interval} = configure(c, %{"tfa_session_lifetime_seconds" => "86400"})
    assert interval.tfa_required_at == org.tfa_required_at
    assert {:ok, disabled} = configure(c, %{"enforcement" => "disabled"})
    refute OrganizationTFA.scheduled?(disabled)
    assert {:ok, _} = configure(c, %{"enforcement" => "transition", "grace_days" => "14"})
  end

  test "suspension retains membership, role, ownership and seat and enrollment restores eligibility" do
    c = context()
    before = Organizations.all_members(c.organization)
    assert {:ok, org} = configure(c, %{"enforcement" => "immediate"})
    assert OrganizationAuth.check(org, c.member) == {:error, :tfa_required}
    assert OrganizationTFA.enrollment_status(org, c.member) == "overdue"
    assert Organizations.all_members(org) == before
    assert Hexpm.Accounts.Seats.used(org) == 2
    session = browser(c.member)
    secret = Hexpm.Accounts.TFA.generate_secret()

    {:ok, user} =
      Users.tfa_enable(c.member, secret, Hexpm.Accounts.TFA.time_based_token(secret),
        audit: audit_data(c.member)
      )

    assert OrganizationTFA.enrollment_status(org, user) == "enabled"
    assert OrganizationAuth.check(org, user, nil, session.id) == {:error, :tfa_required}
    {:ok, :ok} = TFASessions.record_verified!(user, session.id)
    assert OrganizationAuth.check(org, user, nil, session.id) == :ok
    assert Organizations.all_members(org) == before
  end

  test "all cadences expire at the original verification timestamp and changes re-evaluate it" do
    c = context()
    now = DateTime.utc_now()

    for seconds <- [86_400, 604_800, 2_592_000] do
      assert OrganizationTFA.changeset(c.organization, %{tfa_session_lifetime_seconds: seconds}).valid?

      proof_time = DateTime.add(now, -seconds)

      Repo.update_all(from(s in UserSession, where: s.id == ^c.session.id),
        set: [tfa_verified_at: proof_time]
      )

      refute TFASessions.verified?(c.admin, c.session.id, seconds, now)

      assert TFASessions.verified?(
               c.admin,
               c.session.id,
               seconds,
               DateTime.add(now, -1, :microsecond)
             )
    end

    refute OrganizationTFA.changeset(c.organization, %{tfa_session_lifetime_seconds: 3600}).valid?
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
    secret = Hexpm.Accounts.TFA.generate_secret()

    {:ok, user} =
      Users.tfa_enable(user, secret, Hexpm.Accounts.TFA.time_based_token(secret),
        audit: audit_data(user)
      )

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

  test "proof isn't inferred, replacement invalidates it, and copying retains time and revocation" do
    c = context()
    client = insert(:oauth_client)
    target = insert(:oauth_session, user: c.admin, client_id: client.client_id)
    old = DateTime.add(DateTime.utc_now(), -1000)

    Repo.update_all(from(s in UserSession, where: s.id == ^c.session.id),
      set: [tfa_verified_at: old]
    )

    assert TFASessions.proof(c.admin, target.id) == nil
    TFASessions.copy!(c.session.id, target.id, c.admin)
    assert TFASessions.proof(c.admin, target.id).tfa_verified_at == old

    Repo.update_all(from(s in UserSession, where: s.id == ^c.session.id),
      set: [revoked_at: DateTime.utc_now()]
    )

    assert TFASessions.proof(c.admin, target.id) == nil
    Repo.update_all(from(s in UserSession, where: s.id == ^c.session.id), set: [revoked_at: nil])
    secret = Hexpm.Accounts.TFA.generate_secret()
    assert :error = Users.tfa_enable(c.admin, secret, "invalid", audit: audit_data(c.admin))
    assert TFASessions.proof(c.admin, target.id)

    {:ok, updated} =
      Users.tfa_enable(c.admin, secret, Hexpm.Accounts.TFA.time_based_token(secret),
        audit: audit_data(c.admin)
      )

    assert updated.tfa_generation == c.admin.tfa_generation + 1
    refute TFASessions.proof(updated, target.id)
    assert {:error, :credentials_changed} = TFASessions.record_verified!(c.admin, c.session.id)
  end

  test "every human credential is refused without proof and organization-owned credentials are exempt" do
    c = context()
    {:ok, org} = configure(c, %{"enforcement" => "immediate"})
    key = insert(:key, user: c.admin)
    assert OrganizationAuth.check(org, c.admin, key) == {:error, :tfa_personal_key}

    token = %Hexpm.OAuth.Token{
      grant_type: "client_credentials",
      user_id: c.admin.id,
      user_session_id: c.session.id
    }

    assert OrganizationAuth.check(org, c.admin, token) == {:error, :tfa_personal_key}
    assert OrganizationAuth.check(org, c.admin) == {:error, :tfa_required}
    assert OrganizationAuth.check(org, org, key) == :ok
    assert OrganizationAuth.check(insert(:organization), c.admin, key) == :ok
  end

  test "tokens cap scheduled enforcement, distinguish purposes, and refresh preserves proof and absolute expiry" do
    c = context()
    client = insert(:oauth_client)
    cutoff = DateTime.add(DateTime.utc_now(), 120)
    {:ok, org} = configure(c, %{tfa_required_at: cutoff})
    scopes = ["repository:#{org.name}", "docs:#{org.name}", "api:read"]

    {:ok, token} =
      Tokens.create_session_and_token_for_user(
        c.admin,
        client.client_id,
        scopes,
        "authorization_code",
        nil,
        browser_session_id: c.session.id,
        with_refresh_token: true,
        audit: audit_data(c.admin)
      )

    {:ok, claims} = JWT.verify_and_decode(token.access_token)
    assert claims["token_use"] == "access"
    assert claims["exp"] <= DateTime.to_unix(cutoff)
    {:ok, refresh_claims} = JWT.verify_and_decode(token.refresh_token)
    assert refresh_claims["token_use"] == "refresh"
    before = Repo.get!(UserSession, token.user_session_id)
    token = Repo.preload(token, :user)

    {:ok, refreshed} =
      Tokens.revoke_and_create_token(token, client.client_id, scopes, "refresh_token", nil,
        user_session_id: token.user_session_id,
        with_refresh_token: true
      )

    after_session = Repo.get!(UserSession, token.user_session_id)
    assert before.tfa_verified_at == after_session.tfa_verified_at
    assert before.expires_at == after_session.expires_at
    assert token.refresh_token_expires_at == refreshed.refresh_token_expires_at
    {:ok, refresh_claims} = JWT.verify_and_decode(refreshed.refresh_token)
    assert refresh_claims["exp"] <= DateTime.to_unix(before.expires_at)
  end

  test "notifications are durable per revision and obsolete queued notices are cancelled" do
    c = context()
    {:ok, org} = configure(c, %{"enforcement" => "transition", "grace_days" => "14"})
    assert Repo.aggregate(OrganizationTFANotification, :count) == 2
    OrganizationTFANotifications.sweep()
    OrganizationTFANotifications.sweep()
    assert Repo.aggregate(OrganizationTFANotification, :count) == 2
    {:ok, _} = configure(c, %{"enforcement" => "disabled"})

    refute Repo.exists?(
             from(e in Hexpm.Emails.OutboxEntry,
               where: e.scope_key == ^"tfa:organization:#{org.id}"
             )
           )

    assert Repo.aggregate(OrganizationTFANotification, :count) == 2
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

  test "SSO and 2FA expire and renew independently, including SSO exemptions" do
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
      insert(:organization_sso_identity, organization: org, connection: connection, user: c.admin)

    client = insert(:oauth_client)
    target = insert(:oauth_session, user: c.admin, client_id: client.client_id)

    assert OrganizationAuth.required(c.admin, [org.name], target.id) == [
             %{organization: org.name, requirements: ["tfa", "sso"]}
           ]

    sso = Hexpm.Accounts.SSO.establish_org_session!(identity, target.id)

    assert OrganizationAuth.required(c.admin, [org.name], target.id) == [
             %{organization: org.name, requirements: ["tfa"]}
           ]

    {:ok, :ok} = TFASessions.record_verified!(c.admin, target.id)
    assert OrganizationAuth.required(c.admin, [org.name], target.id) == []
    proof_time = TFASessions.proof(c.admin, target.id).tfa_verified_at

    Repo.update_all(from(s in Hexpm.Accounts.SSO.OrgSession, where: s.id == ^sso.id),
      set: [expires_at: DateTime.utc_now()]
    )

    assert OrganizationAuth.required(c.admin, [org.name], target.id) == [
             %{organization: org.name, requirements: ["sso"]}
           ]

    Hexpm.Accounts.SSO.establish_org_session!(identity, target.id)
    assert TFASessions.proof(c.admin, target.id).tfa_verified_at == proof_time

    Repo.update_all(from(s in UserSession, where: s.id == ^target.id),
      set: [tfa_verified_at: DateTime.add(DateTime.utc_now(), -604_801)]
    )

    assert OrganizationAuth.required(c.admin, [org.name], target.id) == [
             %{organization: org.name, requirements: ["tfa"]}
           ]

    Repo.update_all(
      from(m in Hexpm.Accounts.OrganizationUser,
        where: m.organization_id == ^org.id and m.user_id == ^c.admin.id
      ),
      set: [sso_enforcement: "exempt"]
    )

    assert OrganizationAuth.required(c.admin, [org.name], target.id) == [
             %{organization: org.name, requirements: ["tfa"]}
           ]

    assert OrganizationAuth.check(org, c.admin, insert(:key, user: c.admin)) ==
             {:error, :tfa_personal_key}

    {:ok, _} = configure(c, %{"enforcement" => "disabled"})
    assert OrganizationAuth.required(c.admin, [org.name], target.id) == []
    assert Repo.get!(Hexpm.Accounts.SSO.Connection, connection.id).enforcement_mode == "required"
  end

  test "all grant types filter 2FA scopes and preserve unrelated organization access" do
    c = context()
    {:ok, org} = configure(c, %{"enforcement" => "immediate"})
    other = insert(:organization)
    insert(:organization_user, organization: other, user: c.admin, role: "read")
    client = insert(:oauth_client)

    for grant <- [
          "authorization_code",
          "urn:ietf:params:oauth:grant-type:device_code",
          "refresh_token",
          "client_credentials"
        ] do
      token =
        Tokens.create_for_user(
          c.admin,
          client.client_id,
          ["api:read", "repository:#{org.name}", "docs:#{org.name}", "repository:#{other.name}"],
          grant
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
        c.admin,
        client.client_id,
        ["repository:#{org.name}"],
        "client_credentials",
        nil,
        user_session_id: c.session.id,
        with_refresh_token: true
      )
      |> Ecto.Changeset.apply_changes()

    assert token.scopes == []
    assert token.refresh_token == nil
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

    secret = Hexpm.Accounts.TFA.generate_secret()

    {:ok, _} =
      Users.tfa_enable(c.member, secret, Hexpm.Accounts.TFA.time_based_token(secret),
        audit: audit_data(c.member)
      )

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

  test "admission racing with enrollment rechecks the locked credential generation" do
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

  test "suspension notices begin at the exact deadline and personal-key users receive reminders" do
    c = context()
    insert(:key, user: c.admin, permissions: [build(:key_permission, domain: "api")])
    {:ok, org} = configure(c, %{"enforcement" => "transition", "grace_days" => "14"})
    OrganizationTFANotifications.sweep(DateTime.add(org.tfa_required_at, -7 * 86_400))

    assert Repo.aggregate(
             from(n in OrganizationTFANotification, where: n.stage == "seven_days"),
             :count
           ) == 2

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

    secret = Hexpm.Accounts.TFA.generate_secret()

    {:ok, user} =
      Users.tfa_enable(user, secret, Hexpm.Accounts.TFA.time_based_token(secret),
        audit: audit_data(user)
      )

    assert {:error, :seats_exhausted} =
             OrganizationInvitations.accept(invitation, user, audit: audit_data(user))

    refute Repo.get!(Hexpm.Accounts.OrganizationInvitation, invitation.id).accepted_at
    refute Organizations.get_role(org, user)
    assert Hexpm.Accounts.Seats.used(org) == 3
  end

  test "recovery-code rotation with a stale user doesn't restore a replaced authenticator" do
    c = context()
    secret = Hexpm.Accounts.TFA.generate_secret()

    {:ok, replaced} =
      Users.tfa_enable(c.admin, secret, Hexpm.Accounts.TFA.time_based_token(secret),
        audit: audit_data(c.admin)
      )

    rotated = Users.tfa_rotate_recovery_codes(c.admin, audit: audit_data(c.admin))
    assert rotated.tfa.secret == replaced.tfa.secret
    assert rotated.tfa_generation == replaced.tfa_generation
    refute rotated.tfa.recovery_codes == replaced.tfa.recovery_codes
    refute TFASessions.proof(rotated, c.session.id)
  end

  test "membership removal invalidates an open browser authorization" do
    c = context()
    {:ok, org} = configure(c, %{"enforcement" => "immediate"})
    target = insert(:oauth_session, user: c.admin, client_id: insert(:oauth_client).client_id)

    {:ok, authorization} =
      Hexpm.Accounts.SSO.request_authorization(c.admin, target.id, [org.name])

    Repo.delete_all(
      from(m in Hexpm.Accounts.OrganizationUser,
        where: m.organization_id == ^org.id and m.user_id == ^c.admin.id
      )
    )

    assert {:error, :requirements_missing} =
             Hexpm.Accounts.SSO.complete_authorization(authorization, c.admin, c.session.id)

    refute TFASessions.proof(c.admin, target.id)
  end

  test "combined authorization commits both proofs and retains browser revocation and target expiry" do
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
      insert(:organization_sso_identity, organization: org, connection: connection, user: c.admin)

    target = insert(:oauth_session, user: c.admin, client_id: insert(:oauth_client).client_id)

    {:ok, authorization} =
      Hexpm.Accounts.SSO.request_authorization(c.admin, target.id, [org.name])

    assert {:error, :requirements_missing} =
             Hexpm.Accounts.SSO.complete_authorization(authorization, c.admin, c.session.id)

    refute TFASessions.proof(c.admin, target.id)
    source = Hexpm.Accounts.SSO.establish_org_session!(identity, c.session.id)

    assert {:ok, :ok} =
             Hexpm.Accounts.SSO.complete_authorization(authorization, c.admin, c.session.id)

    assert OrganizationAuth.required(c.admin, [org.name], target.id) == []

    assert TFASessions.proof(c.admin, target.id).tfa_verified_at ==
             TFASessions.proof(c.admin, c.session.id).tfa_verified_at

    assert Hexpm.Accounts.SSO.current_org_session(target.id, org.id).authenticated_at ==
             source.authenticated_at

    assert Repo.get!(UserSession, target.id).expires_at == target.expires_at

    Repo.update_all(from(s in UserSession, where: s.id == ^c.session.id),
      set: [revoked_at: DateTime.utc_now()]
    )

    assert OrganizationAuth.required(c.admin, [org.name], target.id) == [
             %{organization: org.name, requirements: ["tfa", "sso"]}
           ]
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
    secret = Hexpm.Accounts.TFA.generate_secret()

    assert {:ok, _} =
             Users.tfa_enable(c.member, secret, Hexpm.Accounts.TFA.time_based_token(secret),
               audit: audit_data(c.member)
             )

    updated = Repo.get!(Hexpm.Emails.OutboxEntry, summary.id)
    assert updated.email["text_body"] =~ "Members suspended because 2FA isn't enabled: none"
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

    secret = Hexpm.Accounts.TFA.generate_secret()

    assert {:ok, _} =
             Users.tfa_enable(c.member, secret, Hexpm.Accounts.TFA.time_based_token(secret),
               audit: audit_data(c.member)
             )

    Repo.update_all(from(e in Hexpm.Emails.OutboxEntry, where: e.id == ^summary.id),
      set: [email: summary.email]
    )

    job = %Oban.Job{args: %{"outbox_entry_id" => summary.id}, attempt: 1, max_attempts: 10}
    assert :ok = Hexpm.Emails.OutboxWorker.perform(job)
    delivered = Repo.get!(Hexpm.Emails.OutboxEntry, summary.id)
    assert delivered.delivered_at
    assert delivered.email["text_body"] =~ "Members suspended because 2FA isn't enabled: none"
    refute delivered.email["text_body"] =~ c.member.username
    assert :ok = Hexpm.Emails.OutboxWorker.perform(job)
    assert Repo.get!(Hexpm.Emails.OutboxEntry, summary.id).delivered_at == delivered.delivered_at
  end
end
