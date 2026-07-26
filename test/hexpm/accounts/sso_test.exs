defmodule Hexpm.Accounts.SSOTest do
  use Hexpm.DataCase

  import ExUnit.CaptureLog

  alias Hexpm.Accounts.{AuditLogs, Organizations, SSO, Users}
  alias Hexpm.Accounts.SSO.{Connection, Features, Identity, OIDC}
  alias Hexpm.Emails.OutboxEntry

  setup :verify_on_exit!

  setup do
    organization = insert(:organization)
    admin = insert(:user)
    insert(:organization_user, organization: organization, user: admin, role: "admin")

    config = Application.fetch_env!(:hexpm, :organization_sso)

    Application.put_env(
      :hexpm,
      :organization_sso,
      Keyword.merge(config, mode: :beta, beta_organizations: [organization.name])
    )

    on_exit(fn -> Application.put_env(:hexpm, :organization_sso, config) end)

    %{organization: organization, admin: admin}
  end

  describe "feature gating" do
    test "requires both beta mode and the organization allowlist", %{organization: organization} do
      assert Features.enabled?(organization)
      assert SSO.available?()

      config = Application.fetch_env!(:hexpm, :organization_sso)

      Application.put_env(
        :hexpm,
        :organization_sso,
        Keyword.put(config, :beta_organizations, [])
      )

      refute Features.enabled?(organization)
      refute SSO.available?()

      Application.put_env(
        :hexpm,
        :organization_sso,
        Keyword.put(config, :mode, :off)
      )

      refute Features.enabled?(organization)
      refute SSO.available?()
    end

    test "enabled mode is limited to paid organizations", %{organization: organization} do
      config = Application.fetch_env!(:hexpm, :organization_sso)
      Application.put_env(:hexpm, :organization_sso, Keyword.put(config, :mode, :enabled))

      assert Features.enabled?(organization)

      refute Features.enabled?(%{
               organization
               | billing_active: false,
                 trial_end: ~U[2020-01-01 00:00:00Z]
             })
    end

    test "enabled mode can be available to all organizations", %{organization: organization} do
      config = Application.fetch_env!(:hexpm, :organization_sso)

      Application.put_env(
        :hexpm,
        :organization_sso,
        Keyword.merge(config, mode: :enabled, all_organizations: true)
      )

      assert Features.enabled?(%{
               organization
               | billing_active: false,
                 trial_end: ~U[2020-01-01 00:00:00Z]
             })
    end
  end

  describe "connection lifecycle" do
    test "configures a provider-neutral connection and redacts secrets", context do
      stub_discovery()

      assert {:ok, connection} = configure_connection(context)
      assert connection.issuer == "https://identity.example.com/oauth2/default"
      assert connection.client_id == "client-id"
      assert connection.client_secret == "client-secret"
      refute inspect(connection) =~ "client-secret"

      assert [audit_log] = AuditLogs.all_by(context.organization)
      assert audit_log.action == "sso.connection.configure"
      refute inspect(audit_log.params) =~ "client-secret"
    end

    test "does not apply Okta domain restrictions", context do
      stub_discovery()

      assert {:ok, connection} =
               SSO.configure(
                 context.organization,
                 %{
                   issuer: "https://identity.example.com/oauth2/default",
                   client_id: "client-id",
                   client_secret: "client-secret"
                 },
                 audit: audit_data(context.admin)
               )

      assert connection.issuer == "https://identity.example.com/oauth2/default"
    end

    test "rejects query and fragment components at the configuration boundary", context do
      assert {:error, %SSO.Error{stage: :url_validation, code: :query_not_allowed}} =
               SSO.configure(
                 context.organization,
                 %{
                   issuer: "https://identity.example.com/tenant?configuration=other",
                   client_id: "client-id",
                   client_secret: "client-secret"
                 },
                 audit: audit_data(context.admin)
               )

      assert {:error, %SSO.Error{stage: :url_validation, code: :fragment_not_allowed}} =
               SSO.configure(
                 context.organization,
                 %{
                   issuer: "https://identity.example.com/tenant#other",
                   client_id: "client-id",
                   client_secret: "client-secret"
                 },
                 audit: audit_data(context.admin)
               )

      refute SSO.get_connection(context.organization)
    end

    test "rechecks administrator access after provider discovery", context do
      second_admin = insert(:user)

      insert(:organization_user,
        organization: context.organization,
        user: second_admin,
        role: "admin"
      )

      parent = self()

      expect(OIDC.Mock, :discover, fn issuer ->
        send(parent, {:discovery_started, self()})

        receive do
          :continue -> {:ok, discovery_metadata(issuer)}
        end
      end)

      task = Task.async(fn -> configure_connection(context) end)
      assert_receive {:discovery_started, task_pid}

      assert {:ok, _membership} =
               Organizations.change_role(
                 context.organization,
                 context.admin,
                 %{"role" => "read"},
                 audit: audit_data(second_admin)
               )

      send(task_pid, :continue)
      assert Task.await(task, 5_000) == {:error, :admin_required}
      refute SSO.get_connection(context.organization)
    end

    test "resolves a blank secret from the locked connection after discovery", context do
      insert(:organization_sso_connection,
        organization: context.organization,
        client_secret: "old-secret",
        enabled_at: nil
      )

      parent = self()

      stub(OIDC.Mock, :discover, fn issuer ->
        if issuer == "https://slow.example.com" do
          send(parent, {:slow_discovery_started, self()})

          receive do
            :continue -> :ok
          end
        end

        {:ok, discovery_metadata(issuer)}
      end)

      task =
        Task.async(fn ->
          receive do
            :go -> :ok
          end

          SSO.configure(
            context.organization,
            %{
              issuer: "https://slow.example.com",
              client_id: "slow-client",
              client_secret: ""
            },
            audit: audit_data(context.admin)
          )
        end)

      Mox.allow(OIDC.Mock, self(), task.pid)
      send(task.pid, :go)
      assert_receive {:slow_discovery_started, task_pid}

      assert {:ok, updated} =
               SSO.configure(
                 context.organization,
                 %{
                   issuer: "https://fast.example.com",
                   client_id: "fast-client",
                   client_secret: "new-secret"
                 },
                 audit: audit_data(context.admin)
               )

      assert updated.client_secret == "new-secret"
      send(task_pid, :continue)

      assert {:ok, configured} = Task.await(task, 5_000)
      assert configured.issuer == "https://slow.example.com"
      assert configured.client_secret == "new-secret"
    end

    test "clears an unfinished rotation when a disabled connection is reconfigured", context do
      connection = configured_and_tested_connection(context)

      assert {:ok, pending} =
               SSO.begin_rotation(context.organization, "replacement-secret",
                 audit: audit_data(context.admin)
               )

      assert pending.pending_client_secret == "replacement-secret"
      stub_discovery()

      assert {:ok, reconfigured} = configure_connection(context)
      assert reconfigured.pending_client_secret == nil
      assert reconfigured.pending_client_secret_tested_at == nil
      assert reconfigured.tested_at == nil
      assert reconfigured.enabled_at == nil
      assert reconfigured.id == connection.id
    end

    test "requires old identities to be unlinked before changing issuer or client ID", context do
      connection = configured_and_tested_connection(context)

      insert(:organization_sso_identity,
        connection: connection,
        organization: context.organization,
        user: context.admin
      )

      assert {:error, :connection_has_identities} =
               SSO.configure(
                 context.organization,
                 %{
                   issuer: "https://other-identity.example.com",
                   client_id: "other-client",
                   client_secret: "other-secret"
                 },
                 audit: audit_data(context.admin)
               )

      assert {:error, :connection_has_identities} =
               SSO.configure(
                 context.organization,
                 %{
                   issuer: connection.issuer,
                   client_id: "replacement-client-id",
                   client_secret: "other-secret"
                 },
                 audit: audit_data(context.admin)
               )
    end

    test "requires an administrator", %{organization: organization} do
      member = insert(:user)
      insert(:organization_user, organization: organization, user: member, role: "read")

      assert {:error, :admin_required} =
               SSO.configure(
                 organization,
                 %{
                   issuer: "https://identity.example.com",
                   client_id: "id",
                   client_secret: "secret"
                 },
                 audit: audit_data(member)
               )
    end

    test "requires a successful test before enablement", context do
      stub_discovery()
      assert {:ok, _connection} = configure_connection(context)

      assert {:error, :connection_not_tested} =
               SSO.enable(context.organization, audit: audit_data(context.admin))

      stub_authorization_uri()

      assert {:ok, transaction, uri} =
               SSO.start_test(
                 context.organization,
                 context.admin,
                 :active,
                 "https://hex.pm/sso/callback"
               )

      assert uri == "https://identity.example.com/authorize"
      transaction = SSO.get_transaction_by_state(transaction.raw_state)

      assert {:ok, :test} =
               SSO.complete_callback(
                 transaction,
                 valid_claims(),
                 context.admin,
                 nil,
                 audit_data(context.admin)
               )

      assert {:ok, connection} =
               SSO.enable(context.organization, audit: audit_data(context.admin))

      assert Connection.enabled?(connection)

      assert {:ok, disabled} = SSO.disable(context.organization, audit: audit_data(context.admin))
      refute Connection.enabled?(disabled)

      actions = context.organization |> AuditLogs.all_by() |> Enum.map(& &1.action)
      assert "sso.connection.configure" in actions
      assert "sso.connection.test" in actions
      assert "sso.connection.enable" in actions
      assert "sso.connection.disable" in actions
    end

    test "binds an active connection test to the configuring administrator", context do
      stub_discovery()
      assert {:ok, connection} = configure_connection(context)
      assert connection.configured_by_user_id == context.admin.id

      second_admin = insert(:user)

      insert(:organization_user,
        organization: context.organization,
        user: second_admin,
        role: "admin"
      )

      assert {:error, :configuration_admin_required} =
               SSO.start_test(
                 context.organization,
                 second_admin,
                 :active,
                 "https://hex.pm/sso/callback"
               )

      stub_authorization_uri()

      assert {:ok, transaction, _uri} =
               SSO.start_test(
                 context.organization,
                 context.admin,
                 :active,
                 "https://hex.pm/sso/callback"
               )

      transaction = SSO.get_transaction_by_state(transaction.raw_state)

      assert {:error, :test_user_mismatch} =
               SSO.complete_callback(
                 transaction,
                 valid_claims(),
                 second_admin,
                 nil,
                 audit_data(second_admin)
               )

      refute SSO.get_connection(context.organization).tested_at
      refute Repo.get!(SSO.Transaction, transaction.id).consumed_at
    end

    test "tests a pending secret before completing an overlap rotation", context do
      connection = configured_and_tested_connection(context)

      assert {:ok, _connection} =
               SSO.enable(context.organization, audit: audit_data(context.admin))

      assert {:ok, pending} =
               SSO.begin_rotation(context.organization, "next-secret",
                 audit: audit_data(context.admin)
               )

      assert pending.client_secret == "client-secret"
      assert pending.pending_client_secret == "next-secret"

      assert {:error, :rotation_not_ready} =
               SSO.promote_rotation(context.organization, audit: audit_data(context.admin))

      stub_authorization_uri(fn received_connection, _transaction, _redirect_uri, secret ->
        assert received_connection.id == connection.id
        assert secret == "next-secret"
      end)

      assert {:ok, transaction, _uri} =
               SSO.start_test(
                 context.organization,
                 context.admin,
                 :pending,
                 "https://hex.pm/sso/callback"
               )

      transaction = SSO.get_transaction_by_state(transaction.raw_state)

      assert {:ok, :test} =
               SSO.complete_callback(
                 transaction,
                 valid_claims(),
                 context.admin,
                 nil,
                 audit_data(context.admin)
               )

      assert {:ok, rotated} =
               SSO.promote_rotation(context.organization, audit: audit_data(context.admin))

      assert rotated.client_secret == "next-secret"
      assert rotated.pending_client_secret == nil
      assert Connection.enabled?(rotated)

      actions = context.organization |> AuditLogs.all_by() |> Enum.map(& &1.action)
      assert "sso.connection.rotation.start" in actions
      assert "sso.connection.rotation.complete" in actions
    end
  end

  describe "identity linking and login" do
    setup context do
      configured_and_tested_connection(context)

      assert {:ok, _connection} =
               SSO.enable(context.organization, audit: audit_data(context.admin))

      member = insert(:user)
      insert(:organization_user, organization: context.organization, user: member)

      Map.merge(context, %{connection: SSO.get_connection(context.organization), member: member})
    end

    test "binds code exchange to the callback URL stored with the transaction", context do
      transaction = start_transaction(context, context.admin)

      assert transaction.redirect_uri == "https://hex.pm/sso/callback"

      assert {:error, %SSO.Error{stage: :callback, code: :redirect_uri_mismatch}} =
               SSO.exchange_code(transaction, "code", "https://evil.example/callback")
    end

    test "requires an account session to start", context do
      outsider = insert(:user)
      stub_authorization_uri()

      assert {:error, :not_member} =
               SSO.start_login(
                 context.organization,
                 outsider,
                 nil,
                 "https://hex.pm/sso/callback"
               )

      refute Repo.exists?(SSO.Transaction)
    end

    test "an unlinked subject hands a member to the link consent step", context do
      transaction = start_transaction(context, context.member)

      assert {:ok, {:link, transaction_id, link_token, _return_path}} =
               complete(transaction, valid_claims(), context.member)

      assert transaction_id == transaction.id
      refute Repo.exists?(Identity)
      refute Repo.exists?(SSO.OrgSession)

      user = Repo.preload(context.member, :emails)
      user_session = browser_session(context.member)

      assert {:ok, {identity, org_session}} =
               SSO.complete_link(
                 transaction_id,
                 link_token,
                 user,
                 user_session.id,
                 audit_data(user)
               )

      assert identity.user_id == context.member.id
      assert identity.issuer == "https://identity.example.com/oauth2/default"
      assert identity.subject == "00u123"

      # Consent completes an authentication, so it unlocks the organization.
      assert org_session.identity_id == identity.id

      assert SSO.current_org_session(user_session.id, context.organization.id).id ==
               org_session.id

      actions = context.organization |> AuditLogs.all_by() |> Enum.map(& &1.action)
      assert "sso.identity.link" in actions
      assert "sso.login" in actions
    end

    test "an unlinked subject refuses a nonmember and creates nothing", context do
      outsider = insert(:user)

      organization_user =
        insert(:organization_user, organization: context.organization, user: outsider)

      transaction = start_transaction(context, outsider)
      Repo.delete!(organization_user)

      assert {:error, :not_member} = complete(transaction, valid_claims(), outsider)

      refute Repo.exists?(Identity)
      refute Repo.exists?(SSO.OrgSession)
      assert [%{stage: "login", code: "not_member"}] = SSO.failures(context.connection)
    end

    test "a linked subject owned by the signed-in account establishes org access", context do
      identity = link_identity(context, context.member)
      user_session = browser_session(context.member)
      transaction = start_transaction(context, context.member)

      assert {:ok, {:login, user, org_session, _return_path}} =
               complete(transaction, valid_claims(), context.member, user_session.id)

      assert user.id == context.member.id
      assert org_session.user_id == context.member.id
      assert org_session.organization_id == context.organization.id
      assert org_session.identity_id == identity.id
      assert org_session.user_session_id == user_session.id
      assert org_session.revoked_at == nil

      assert DateTime.diff(org_session.expires_at, org_session.authenticated_at) ==
               24 * 60 * 60

      assert SSO.current_org_session(user_session.id, context.organization.id).id ==
               org_session.id

      actions = context.organization |> AuditLogs.all_by() |> Enum.map(& &1.action)
      assert "sso.login" in actions
    end

    test "re-authenticating in the same browser session refreshes the same row", context do
      link_identity(context, context.member)
      user_session = browser_session(context.member)

      assert {:ok, {:login, _user, first, _return}} =
               context
               |> start_transaction(context.member)
               |> complete(valid_claims(), context.member, user_session.id)

      assert {:ok, {:login, _user, second, _return}} =
               context
               |> start_transaction(context.member)
               |> complete(valid_claims(), context.member, user_session.id)

      assert second.id == first.id
      assert Repo.aggregate(SSO.OrgSession, :count) == 1
    end

    test "a subject owned by another account refuses", context do
      other = insert(:user)
      insert(:organization_user, organization: context.organization, user: other)
      identity = link_identity(context, other)
      transaction = start_transaction(context, context.member)

      assert {:error, :session_user_mismatch} =
               complete(transaction, valid_claims(), context.member)

      assert [%Identity{} = unchanged] = Repo.all(Identity)
      assert unchanged.id == identity.id
      assert unchanged.user_id == other.id
      refute Repo.exists?(SSO.OrgSession)
      assert Repo.get!(SSO.Transaction, transaction.id).consumed_at
    end

    test "the signed-in account already holding a different subject refuses", context do
      link_identity(context, context.member, subject: "00u-original")
      transaction = start_transaction(context, context.member)

      assert {:error, :identity_conflict} =
               complete(transaction, %{valid_claims() | subject: "00u-different"}, context.member)

      assert [%Identity{subject: "00u-original"}] = Repo.all(Identity)
      refute Repo.exists?(SSO.OrgSession)
    end

    test "a transaction started by a different account refuses", context do
      other = insert(:user)
      insert(:organization_user, organization: context.organization, user: other)
      link_identity(context, other)
      transaction = start_transaction(context, context.member)

      assert {:error, :session_user_mismatch} = complete(transaction, valid_claims(), other)
      refute Repo.exists?(SSO.OrgSession)
    end

    test "a linked identity belonging to a nonmember is deleted and refused", context do
      link_identity(context, context.member)
      transaction = start_transaction(context, context.member)

      Repo.delete_all(
        from(organization_user in Hexpm.Accounts.OrganizationUser,
          where: organization_user.user_id == ^context.member.id,
          where: organization_user.organization_id == ^context.organization.id
        )
      )

      assert {:error, :not_member} = complete(transaction, valid_claims(), context.member)

      refute Repo.exists?(Identity)
      refute Repo.exists?(SSO.OrgSession)
      assert [%{stage: "login", code: "not_member"}] = SSO.failures(context.connection)
    end

    # Ecto's sandbox hands both tasks one connection, so this asserts that a
    # second callback on a consumed transaction fails rather than that the locks
    # work. Real concurrency is a controlled-harness row in the runbook.
    test "a second callback on the same transaction cannot also succeed", context do
      link_identity(context, context.member)
      user_session = browser_session(context.member)
      transaction = start_transaction(context, context.member)
      parent = self()

      tasks =
        for _attempt <- 1..2 do
          Task.async(fn ->
            Ecto.Adapters.SQL.Sandbox.allow(Hexpm.RepoBase, parent, self())
            send(parent, {:ready, self()})

            receive do
              :go ->
                SSO.complete_callback(
                  transaction,
                  valid_claims(),
                  context.member,
                  user_session.id,
                  audit_data(context.member)
                )
            end
          end)
        end

      for task <- tasks do
        assert_receive {:ready, pid}
        send(pid, :go)
        _ = task
      end

      results = Enum.map(tasks, &Task.await/1)

      assert Enum.count(results, &match?({:ok, {:login, _user, _session, _return}}, &1)) == 1
      assert Enum.count(results, &match?({:error, :transaction_already_used}, &1)) == 1
      assert Repo.aggregate(SSO.OrgSession, :count) == 1
    end

    test "abandoning a login consumes the transaction and records the failure", context do
      transaction = start_transaction(context, context.member)

      assert :ok = SSO.abandon_login(transaction, :callback, :account_session_required)

      assert Repo.get!(SSO.Transaction, transaction.id).consumed_at

      assert [%{stage: "callback", code: "account_session_required"}] =
               SSO.failures(context.connection)
    end

    test "an organization access session dies with its browser session", context do
      link_identity(context, context.member)
      user_session = browser_session(context.member)

      assert {:ok, {:login, _user, org_session, _return}} =
               context
               |> start_transaction(context.member)
               |> complete(valid_claims(), context.member, user_session.id)

      assert SSO.current_org_session(user_session.id, context.organization.id)

      Hexpm.UserSessions.revoke(user_session, nil, audit: audit_data(context.member))

      refute SSO.current_org_session(user_session.id, context.organization.id)
      assert Repo.get!(SSO.OrgSession, org_session.id).revoked_at
    end

    test "an organization access session dies when the parent is revoked in bulk", context do
      # revoke_all/2 does a raw update_all on user_sessions and never touches
      # organization_sso_sessions, so the parent check in current_org_session/2
      # is the only thing enforcing this. Password reset uses this path.
      link_identity(context, context.member)
      user_session = browser_session(context.member)

      assert {:ok, {:login, _user, org_session, _return}} =
               context
               |> start_transaction(context.member)
               |> complete(valid_claims(), context.member, user_session.id)

      assert SSO.current_org_session(user_session.id, context.organization.id)

      {sessions, tokens} = Hexpm.UserSessions.revoke_all(context.member)
      Repo.update_all(sessions, [])
      Repo.update_all(tokens, [])

      refute SSO.current_org_session(user_session.id, context.organization.id)
      assert Repo.get!(SSO.OrgSession, org_session.id).revoked_at == nil
    end

    test "an organization access session dies when the parent expires", context do
      link_identity(context, context.member)
      user_session = browser_session(context.member)

      assert {:ok, {:login, _user, _org_session, _return}} =
               context
               |> start_transaction(context.member)
               |> complete(valid_claims(), context.member, user_session.id)

      Repo.update_all(
        from(session in Hexpm.UserSession, where: session.id == ^user_session.id),
        set: [expires_at: DateTime.add(DateTime.utc_now(), -1, :second)]
      )

      refute SSO.current_org_session(user_session.id, context.organization.id)
    end

    test "an organization access session is scoped to its own organization", context do
      other_organization = insert(:organization)
      insert(:organization_user, organization: other_organization, user: context.member)

      link_identity(context, context.member)
      user_session = browser_session(context.member)

      assert {:ok, {:login, _user, _org_session, _return}} =
               context
               |> start_transaction(context.member)
               |> complete(valid_claims(), context.member, user_session.id)

      assert SSO.current_org_session(user_session.id, context.organization.id)
      refute SSO.current_org_session(user_session.id, other_organization.id)
    end

    test "a second browser session does not inherit the first one's access", context do
      link_identity(context, context.member)
      first = browser_session(context.member)

      assert {:ok, {:login, _user, _org_session, _return}} =
               context
               |> start_transaction(context.member)
               |> complete(valid_claims(), context.member, first.id)

      second = browser_session(context.member)

      assert SSO.current_org_session(first.id, context.organization.id)
      refute SSO.current_org_session(second.id, context.organization.id)
    end

    test "deleting an identity row cascades its organization access sessions", context do
      # The application deletes these explicitly, but the foreign key is what
      # actually guarantees it. Assert the constraint, not the caller.
      identity = link_identity(context, context.member)
      user_session = browser_session(context.member)
      SSO.establish_org_session!(identity, user_session.id)

      assert Repo.exists?(SSO.OrgSession)
      Repo.delete_all(from(candidate in Identity, where: candidate.id == ^identity.id))
      refute Repo.exists?(SSO.OrgSession)
    end

    test "an expired organization access session is no longer current", context do
      link_identity(context, context.member)
      user_session = browser_session(context.member)

      assert {:ok, {:login, _user, org_session, _return}} =
               context
               |> start_transaction(context.member)
               |> complete(valid_claims(), context.member, user_session.id)

      Repo.update_all(
        from(session in SSO.OrgSession, where: session.id == ^org_session.id),
        set: [expires_at: DateTime.add(DateTime.utc_now(), -1, :second)]
      )

      refute SSO.current_org_session(user_session.id, context.organization.id)
    end

    test "unlinking an identity ends the organization access it granted", context do
      link_identity(context, context.member)
      user_session = browser_session(context.member)

      assert {:ok, {:login, _user, _org_session, _return}} =
               context
               |> start_transaction(context.member)
               |> complete(valid_claims(), context.member, user_session.id)

      assert {:ok, %Identity{}} =
               SSO.unlink_identity(context.organization, context.member,
                 audit: audit_data(context.admin)
               )

      refute Repo.exists?(SSO.OrgSession)
      refute SSO.current_org_session(user_session.id, context.organization.id)
    end

    test "removing a member ends the organization access it granted", context do
      link_identity(context, context.member)
      user_session = browser_session(context.member)

      assert {:ok, {:login, _user, _org_session, _return}} =
               context
               |> start_transaction(context.member)
               |> complete(valid_claims(), context.member, user_session.id)

      assert :ok =
               Organizations.remove_member(context.organization, context.member,
                 audit: audit_data(context.admin)
               )

      refute Repo.exists?(SSO.OrgSession)
      refute Repo.exists?(Identity)
    end

    test "a provider email change notifies the member without changing their addresses",
         context do
      link_identity(context, context.member, provider_email: "old@example.com")
      user_session = browser_session(context.member)

      assert {:ok, {:login, _user, _org_session, _return}} =
               context
               |> start_transaction(context.member)
               |> complete(valid_claims("new@example.com"), context.member, user_session.id)

      assert Repo.one!(Identity).provider_email == "new@example.com"

      emails =
        context.member.id
        |> Users.get_by_id([:emails])
        |> Map.fetch!(:emails)
        |> Enum.map(& &1.email)

      refute "new@example.com" in emails

      assert Repo.exists?(
               from(entry in OutboxEntry, where: entry.category == "sso.email_mismatch")
             )
    end

    test "notifications are queued under the member's ordering key", context do
      link_identity(context, context.member)

      assert {:ok, %Identity{}} =
               SSO.unlink_identity(context.organization, context.member,
                 audit: audit_data(context.admin)
               )

      ordering_key = sso_ordering_key(context.connection, context.member)

      assert Repo.exists?(
               from(entry in OutboxEntry,
                 where: entry.ordering_key == ^ordering_key,
                 where: entry.category == "sso.identity_unlinked"
               )
             )
    end
  end

  defp start_transaction(context, user) do
    stub_authorization_uri()

    assert {:ok, transaction, _uri} =
             SSO.start_login(context.organization, user, nil, "https://hex.pm/sso/callback")

    SSO.get_transaction_by_state(transaction.raw_state)
  end

  defp complete(transaction, claims, user, user_session_id \\ nil) do
    SSO.complete_callback(transaction, claims, user, user_session_id, audit_data(user))
  end

  defp link_identity(context, user, attrs \\ []) do
    insert(
      :organization_sso_identity,
      Keyword.merge(
        [
          connection: context.connection,
          organization: context.organization,
          user: user
        ],
        attrs
      )
    )
  end

  defp browser_session(user) do
    {:ok, session, _token} =
      Hexpm.UserSessions.create_browser_session(user, audit: audit_data(user))

    session
  end

  defp sso_ordering_key(connection, user), do: "sso:#{connection.id}:#{user.id}"

  describe "return paths" do
    test "allows only the selected organization dashboard", context do
      base = "/dashboard/orgs/#{context.organization.name}"

      assert SSO.allowed_return_path(context.organization, base) == base

      assert SSO.allowed_return_path(context.organization, base <> "/packages?sort=name") ==
               base <> "/packages?sort=name"

      assert SSO.allowed_return_path(context.organization, "/dashboard/profile") == nil
      assert SSO.allowed_return_path(context.organization, "//evil.example") == nil
      assert SSO.allowed_return_path(context.organization, "/\\evil.example") == nil
      assert SSO.allowed_return_path(context.organization, base <> "-attacker") == nil
      assert SSO.allowed_return_path(context.organization, base <> "/../other") == nil
      assert SSO.allowed_return_path(context.organization, base <> "/%2e%2e/other") == nil
      assert SSO.allowed_return_path(context.organization, base <> "/%5cevil") == nil
    end
  end

  test "does not emit sensitive SSO values in Ecto query logs", context do
    client_secret = "query-log-client-secret"
    provider_subject = "query-log-provider-subject"
    provider_email = "query-log-provider@example.com"

    log =
      capture_log([level: :debug], fn ->
        stub_discovery()

        assert {:ok, connection} =
                 SSO.configure(
                   context.organization,
                   %{
                     issuer: "https://identity.example.com/oauth2/default",
                     client_id: "client-id",
                     client_secret: client_secret
                   },
                   audit: audit_data(context.admin)
                 )

        connection =
          Repo.update!(Ecto.Changeset.change(connection, tested_at: DateTime.utc_now()))

        assert {:ok, _connection} =
                 SSO.enable(context.organization, audit: audit_data(context.admin))

        stub_authorization_uri()

        assert {:ok, transaction, _uri} =
                 SSO.start_login(
                   context.organization,
                   context.admin,
                   nil,
                   "https://hex.pm/sso/callback"
                 )

        send(
          self(),
          {:sensitive_transaction_values, transaction.raw_state, transaction.nonce,
           transaction.code_verifier}
        )

        transaction = SSO.get_transaction_by_state(transaction.raw_state)

        claims = %{
          valid_claims(provider_email)
          | subject: provider_subject
        }

        assert {:ok, {:link, _transaction_id, link_token, _return_path}} =
                 SSO.complete_callback(
                   transaction,
                   claims,
                   context.admin,
                   nil,
                   audit_data(context.admin)
                 )

        send(self(), {:sensitive_link_token, link_token})
        assert connection.client_secret == client_secret
      end)

    assert_receive {:sensitive_transaction_values, state, nonce, verifier}
    assert_receive {:sensitive_link_token, link_token}

    for value <- [
          client_secret,
          provider_subject,
          provider_email,
          state,
          nonce,
          verifier,
          link_token
        ] do
      refute log =~ value
    end
  end

  describe "failure diagnostics" do
    test "records the failing user only for post-proof codes", context do
      connection = configured_and_tested_connection(context)
      member = insert(:user)

      assert {:ok, not_member} = SSO.record_failure(connection, :link, :not_member, member)
      assert not_member.user_id == member.id

      assert SSO.failure_message(not_member) ==
               "The Hexpm account is not a member of the organization"

      assert {:ok, conflict} =
               SSO.record_failure(
                 connection,
                 :link,
                 {:identity_conflict, %Ecto.Changeset{}},
                 member
               )

      assert conflict.user_id == member.id

      assert SSO.failure_message(conflict) ==
               "The SSO identity or Hexpm account is already linked"

      assert {:ok, redacted} = SSO.record_failure(connection, :callback, :issuer_mismatch, member)
      assert is_nil(redacted.user_id)
    end

    test "exposes the linked user on user-bearing failures", context do
      connection = configured_and_tested_connection(context)
      member = insert(:user)

      assert {:ok, _failure} = SSO.record_failure(connection, :link, :not_member, member)

      assert [%{code: "not_member", user: %{username: username}}] = SSO.failures(connection)
      assert username == member.username
    end
  end

  defp configure_connection(context) do
    SSO.configure(
      context.organization,
      %{
        issuer: "https://identity.example.com/oauth2/default",
        client_id: "client-id",
        client_secret: "client-secret"
      },
      audit: audit_data(context.admin)
    )
  end

  defp configured_and_tested_connection(context) do
    stub_discovery()
    assert {:ok, connection} = configure_connection(context)
    Repo.update!(Ecto.Changeset.change(connection, tested_at: DateTime.utc_now()))
  end

  defp stub_discovery do
    Mox.stub(OIDC.Mock, :discover, fn issuer ->
      assert issuer == "https://identity.example.com/oauth2/default"
      {:ok, discovery_metadata(issuer)}
    end)
  end

  defp discovery_metadata(issuer) do
    expires_at = DateTime.add(DateTime.utc_now(), 3_600, :second)

    %{
      discovery_document: %{
        "issuer" => issuer,
        "authorization_endpoint" => "https://identity.example.com/authorize",
        "token_endpoint" => "https://identity.example.com/token",
        "jwks_uri" => "https://identity.example.com/keys"
      },
      jwks_document: %{"keys" => [%{"kty" => "RSA", "kid" => "key-1"}]},
      discovery_expires_at: expires_at,
      jwks_expires_at: expires_at,
      metadata_expires_at: expires_at
    }
  end

  defp stub_authorization_uri(
         assertion \\ fn _connection, _transaction, _redirect_uri, _secret -> :ok end
       ) do
    Mox.stub(OIDC.Mock, :authorization_uri, fn connection, transaction, redirect_uri, secret ->
      assertion.(connection, transaction, redirect_uri, secret)
      assert transaction.raw_state
      assert transaction.nonce
      assert transaction.code_verifier
      assert redirect_uri == "https://hex.pm/sso/callback"
      {:ok, "https://identity.example.com/authorize"}
    end)
  end

  defp valid_claims(email \\ "admin@example.com") do
    %{
      issuer: "https://identity.example.com/oauth2/default",
      subject: "00u123",
      email: email,
      jwks_document: nil
    }
  end
end
