defmodule Hexpm.Accounts.SSOTest do
  use Hexpm.DataCase

  import ExUnit.CaptureLog

  alias Hexpm.Accounts.{AuditLogs, Organizations, SSO}
  alias Hexpm.Accounts.SSO.{Connection, Features, Identity, Notification, OIDC}

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

      config = Application.fetch_env!(:hexpm, :organization_sso)

      Application.put_env(
        :hexpm,
        :organization_sso,
        Keyword.put(config, :beta_organizations, [])
      )

      refute Features.enabled?(organization)

      Application.put_env(
        :hexpm,
        :organization_sso,
        Keyword.put(config, :mode, :off)
      )

      refute Features.enabled?(organization)
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

    test "requires old identities to be unlinked before changing issuer", context do
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
    test "binds code exchange to the callback URL stored with the transaction", context do
      configured_and_tested_connection(context)

      assert {:ok, _connection} =
               SSO.enable(context.organization, audit: audit_data(context.admin))

      stub_authorization_uri()

      assert {:ok, transaction, _uri} =
               SSO.start_login(context.organization, nil, "https://hex.pm/sso/callback")

      transaction = SSO.get_transaction_by_state(transaction.raw_state)
      assert transaction.redirect_uri == "https://hex.pm/sso/callback"

      assert {:error, %SSO.Error{stage: :callback, code: :redirect_uri_mismatch}} =
               SSO.exchange_code(transaction, "code", "https://evil.example/callback")
    end

    test "concurrent callbacks yield at most one success", context do
      configured_and_tested_connection(context)

      assert {:ok, _connection} =
               SSO.enable(context.organization, audit: audit_data(context.admin))

      stub_authorization_uri()

      assert {:ok, transaction, _uri} =
               SSO.start_login(context.organization, nil, "https://hex.pm/sso/callback")

      transaction = SSO.get_transaction_by_state(transaction.raw_state)
      parent = self()

      tasks =
        for _attempt <- 1..2 do
          Task.async(fn ->
            send(parent, {:ready, self()})

            receive do
              :go ->
                SSO.complete_callback(transaction, valid_claims(), nil, %{
                  audit_data(context.admin)
                  | user: nil
                })
            end
          end)
        end

      pids =
        for _task <- tasks do
          assert_receive {:ready, pid}
          pid
        end

      Enum.each(pids, &send(&1, :go))

      results = Enum.map(tasks, &Task.await(&1, 5_000))
      assert Enum.count(results, &match?({:ok, {:link, _, _, _}}, &1)) == 1
      assert Enum.count(results, &(&1 == {:error, :transaction_already_used})) == 1
    end

    test "persists a refreshed JWKS document and its cache expiry", context do
      configured_and_tested_connection(context)

      assert {:ok, _connection} =
               SSO.enable(context.organization, audit: audit_data(context.admin))

      stub_authorization_uri()

      assert {:ok, transaction, _uri} =
               SSO.start_login(context.organization, nil, "https://hex.pm/sso/callback")

      transaction = SSO.get_transaction_by_state(transaction.raw_state)
      jwks_expires_at = DateTime.add(DateTime.utc_now(), 120, :second)
      jwks_document = %{"keys" => [%{"kty" => "RSA", "kid" => "rotated-key"}]}

      claims =
        valid_claims()
        |> Map.put(:jwks_document, jwks_document)
        |> Map.put(:jwks_expires_at, jwks_expires_at)

      assert {:ok, {:link, _transaction_id, _link_token, _return_path}} =
               SSO.complete_callback(transaction, claims, nil, %{
                 audit_data(context.admin)
                 | user: nil
               })

      connection = SSO.get_connection(context.organization)
      assert connection.jwks_document == jwks_document
      assert connection.jwks_expires_at == jwks_expires_at
      assert connection.metadata_expires_at == jwks_expires_at
    end

    test "simultaneous starts use distinct state, nonce, and PKCE values", context do
      configured_and_tested_connection(context)

      assert {:ok, _connection} =
               SSO.enable(context.organization, audit: audit_data(context.admin))

      stub_authorization_uri()

      assert {:ok, first, _uri} =
               SSO.start_login(context.organization, nil, "https://hex.pm/sso/callback")

      assert {:ok, second, _uri} =
               SSO.start_login(context.organization, nil, "https://hex.pm/sso/callback")

      refute first.raw_state == second.raw_state
      refute first.nonce == second.nonce
      refute first.code_verifier == second.code_verifier
    end

    test "expired state cannot be loaded for callback processing", context do
      configured_and_tested_connection(context)

      assert {:ok, _connection} =
               SSO.enable(context.organization, audit: audit_data(context.admin))

      stub_authorization_uri()

      assert {:ok, transaction, _uri} =
               SSO.start_login(context.organization, nil, "https://hex.pm/sso/callback")

      Repo.update!(
        Ecto.Changeset.change(transaction,
          expires_at: DateTime.add(DateTime.utc_now(), -1, :second)
        )
      )

      refute SSO.get_transaction_by_state(transaction.raw_state)
    end

    test "requires explicit linking to an existing organization member", context do
      configured_and_tested_connection(context)

      assert {:ok, _connection} =
               SSO.enable(context.organization, audit: audit_data(context.admin))

      stub_authorization_uri()

      assert {:ok, transaction, _uri} =
               SSO.start_login(
                 context.organization,
                 "/dashboard/orgs/#{context.organization.name}",
                 "https://hex.pm/sso/callback"
               )

      transaction = SSO.get_transaction_by_state(transaction.raw_state)

      assert {:ok, {:link, transaction_id, link_token, return_path}} =
               SSO.complete_callback(transaction, valid_claims(), nil, %{
                 audit_data(context.admin)
                 | user: nil
               })

      assert return_path == "/dashboard/orgs/#{context.organization.name}"
      assert Repo.all(Identity) == []

      assert {:error, :account_proof_required} =
               SSO.complete_link(
                 transaction_id,
                 link_token,
                 context.admin,
                 audit_data(context.admin)
               )

      assert {:ok, _transaction} = SSO.prove_link(transaction_id, link_token, context.admin)

      assert {:ok, identity} =
               SSO.complete_link(
                 transaction_id,
                 link_token,
                 context.admin,
                 audit_data(context.admin)
               )

      assert identity.user_id == context.admin.id
      assert identity.subject == "00u123"
      refute inspect(identity) =~ "00u123"

      linked_transaction = Repo.get!(SSO.Transaction, transaction_id)
      assert linked_transaction.subject == nil
      assert linked_transaction.provider_email == nil

      assert {:error, :link_already_used} =
               SSO.complete_link(
                 transaction_id,
                 link_token,
                 context.admin,
                 audit_data(context.admin)
               )
    end

    test "cancel invalidates the server-side link token and purges copied identity data",
         context do
      configured_and_tested_connection(context)

      assert {:ok, _connection} =
               SSO.enable(context.organization, audit: audit_data(context.admin))

      stub_authorization_uri()

      assert {:ok, transaction, _uri} =
               SSO.start_login(context.organization, nil, "https://hex.pm/sso/callback")

      transaction = SSO.get_transaction_by_state(transaction.raw_state)

      assert {:ok, {:link, transaction_id, link_token, _return_path}} =
               SSO.complete_callback(transaction, valid_claims(), nil, %{
                 audit_data(context.admin)
                 | user: nil
               })

      assert {:ok, _transaction} = SSO.prove_link(transaction_id, link_token, context.admin)
      assert {:ok, cancelled} = SSO.cancel_link(transaction_id, link_token)
      assert cancelled.cancelled_at
      assert cancelled.subject == nil
      assert cancelled.provider_email == nil
      refute SSO.get_pending_link(transaction_id, link_token)

      assert {:error, :link_cancelled} =
               SSO.complete_link(
                 transaction_id,
                 link_token,
                 context.admin,
                 audit_data(context.admin)
               )
    end

    test "a second subject cannot link to an account already linked on the connection", context do
      configured_and_tested_connection(context)

      assert {:ok, _connection} =
               SSO.enable(context.organization, audit: audit_data(context.admin))

      stub_authorization_uri()

      for subject <- ["subject-one", "subject-two"] do
        assert {:ok, transaction, _uri} =
                 SSO.start_login(context.organization, nil, "https://hex.pm/sso/callback")

        transaction = SSO.get_transaction_by_state(transaction.raw_state)
        claims = Map.put(valid_claims(), :subject, subject)

        assert {:ok, {:link, transaction_id, link_token, _return_path}} =
                 SSO.complete_callback(transaction, claims, nil, %{
                   audit_data(context.admin)
                   | user: nil
                 })

        assert {:ok, _transaction} = SSO.prove_link(transaction_id, link_token, context.admin)

        if subject == "subject-one" do
          assert {:ok, _identity} =
                   SSO.complete_link(
                     transaction_id,
                     link_token,
                     context.admin,
                     audit_data(context.admin)
                   )
        else
          assert {:error, {:identity_conflict, _changeset}} =
                   SSO.complete_link(
                     transaction_id,
                     link_token,
                     context.admin,
                     audit_data(context.admin)
                   )
        end
      end
    end

    test "the same issuer and subject cannot map to a second account on one connection",
         context do
      connection = configured_and_tested_connection(context)

      insert(:organization_sso_identity,
        connection: connection,
        organization: context.organization,
        user: context.admin,
        issuer: connection.issuer,
        subject: "shared-subject"
      )

      member = insert(:user)
      insert(:organization_user, organization: context.organization, user: member, role: "read")

      changeset =
        Identity.changeset(%Identity{}, %{
          connection_id: connection.id,
          organization_id: context.organization.id,
          user_id: member.id,
          issuer: connection.issuer,
          subject: "shared-subject"
        })

      assert {:error, changeset} = Repo.insert(changeset)
      assert {"has already been taken", metadata} = changeset.errors[:connection_id]
      assert metadata[:constraint_name] == "organization_sso_identities_external_identity_index"
      assert Repo.aggregate(Identity, :count) == 1
    end

    test "the same issuer and subject remain isolated across organization connections", context do
      connection = configured_and_tested_connection(context)

      first =
        insert(:organization_sso_identity,
          connection: connection,
          organization: context.organization,
          user: context.admin,
          issuer: "https://shared.example.com",
          subject: "shared-subject"
        )

      other_organization = insert(:organization)

      insert(:organization_user,
        organization: other_organization,
        user: context.admin,
        role: "read"
      )

      other_connection =
        insert(:organization_sso_connection,
          organization: other_organization,
          issuer: "https://shared.example.com"
        )

      second =
        insert(:organization_sso_identity,
          connection: other_connection,
          organization: other_organization,
          user: context.admin,
          issuer: "https://shared.example.com",
          subject: "shared-subject"
        )

      assert first.connection_id != second.connection_id
      assert Repo.aggregate(Identity, :count) == 2
    end

    test "the database rejects an identity whose organization does not own its connection",
         context do
      connection = configured_and_tested_connection(context)
      other_organization = insert(:organization)

      changeset =
        Identity.changeset(%Identity{}, %{
          connection_id: connection.id,
          organization_id: other_organization.id,
          user_id: context.admin.id,
          issuer: connection.issuer,
          subject: "cross-organization-subject"
        })

      assert {:error, changeset} = Repo.insert(changeset)
      assert {"does not exist", _metadata} = changeset.errors[:connection_id]
    end

    test "rejects a transaction after its connection metadata version changes", context do
      connection = configured_and_tested_connection(context)

      assert {:ok, _connection} =
               SSO.enable(context.organization, audit: audit_data(context.admin))

      stub_authorization_uri()

      assert {:ok, transaction, _uri} =
               SSO.start_login(context.organization, nil, "https://hex.pm/sso/callback")

      assert {:ok, refreshed} = SSO.refresh_metadata(connection)
      assert refreshed.version > transaction.connection_version

      transaction = SSO.get_transaction_by_state(transaction.raw_state)

      assert {:error, :connection_configuration_changed} =
               SSO.exchange_code(transaction, "code", "https://hex.pm/sso/callback")
    end

    test "rejects a pending-secret test after the replacement changes", context do
      configured_and_tested_connection(context)

      assert {:ok, _connection} =
               SSO.begin_rotation(context.organization, "replacement-a",
                 audit: audit_data(context.admin)
               )

      stub_authorization_uri()

      assert {:ok, transaction, _uri} =
               SSO.start_test(
                 context.organization,
                 context.admin,
                 :pending,
                 "https://hex.pm/sso/callback"
               )

      assert {:ok, _connection} =
               SSO.begin_rotation(context.organization, "replacement-b",
                 audit: audit_data(context.admin)
               )

      transaction = SSO.get_transaction_by_state(transaction.raw_state)

      assert {:error, :connection_credentials_changed} =
               SSO.exchange_code(transaction, "code", "https://hex.pm/sso/callback")
    end

    test "refuses to link a non-member and never creates membership", context do
      configured_and_tested_connection(context)

      assert {:ok, _connection} =
               SSO.enable(context.organization, audit: audit_data(context.admin))

      stub_authorization_uri()
      outsider = insert(:user)

      assert {:ok, transaction, _uri} =
               SSO.start_login(context.organization, nil, "https://hex.pm/sso/callback")

      transaction = SSO.get_transaction_by_state(transaction.raw_state)

      assert {:ok, {:link, transaction_id, link_token, _return_path}} =
               SSO.complete_callback(transaction, valid_claims(), nil, %{
                 audit_data(context.admin)
                 | user: nil
               })

      assert {:error, :not_member} = SSO.prove_link(transaction_id, link_token, outsider)

      refute Organizations.access?(context.organization, outsider, "read")
      assert Repo.all(Identity) == []
    end

    test "refuses to finish a pending link after the connection is disabled", context do
      configured_and_tested_connection(context)

      assert {:ok, _connection} =
               SSO.enable(context.organization, audit: audit_data(context.admin))

      stub_authorization_uri()

      assert {:ok, transaction, _uri} =
               SSO.start_login(context.organization, nil, "https://hex.pm/sso/callback")

      transaction = SSO.get_transaction_by_state(transaction.raw_state)

      assert {:ok, {:link, transaction_id, link_token, _return_path}} =
               SSO.complete_callback(transaction, valid_claims(), nil, %{
                 audit_data(context.admin)
                 | user: nil
               })

      assert {:ok, _transaction} = SSO.prove_link(transaction_id, link_token, context.admin)

      assert {:ok, _connection} =
               SSO.disable(context.organization, audit: audit_data(context.admin))

      assert {:error, :connection_disabled} =
               SSO.complete_link(
                 transaction_id,
                 link_token,
                 context.admin,
                 audit_data(context.admin)
               )

      assert Repo.all(Identity) == []
    end

    test "disable rejects an in-flight login callback", context do
      configured_and_tested_connection(context)

      assert {:ok, _connection} =
               SSO.enable(context.organization, audit: audit_data(context.admin))

      stub_authorization_uri()

      assert {:ok, transaction, _uri} =
               SSO.start_login(context.organization, nil, "https://hex.pm/sso/callback")

      assert {:ok, _connection} =
               SSO.disable(context.organization, audit: audit_data(context.admin))

      transaction = SSO.get_transaction_by_state(transaction.raw_state)

      assert {:error, :connection_disabled} =
               SSO.complete_callback(transaction, valid_claims(), nil, %{
                 audit_data(context.admin)
                 | user: nil
               })
    end

    test "re-enabling does not revive a login started before disable", context do
      configured_and_tested_connection(context)

      assert {:ok, _connection} =
               SSO.enable(context.organization, audit: audit_data(context.admin))

      stub_authorization_uri()

      assert {:ok, transaction, _uri} =
               SSO.start_login(context.organization, nil, "https://hex.pm/sso/callback")

      assert {:ok, _connection} =
               SSO.disable(context.organization, audit: audit_data(context.admin))

      assert {:ok, _connection} =
               SSO.enable(context.organization, audit: audit_data(context.admin))

      transaction = SSO.get_transaction_by_state(transaction.raw_state)

      assert {:error, :connection_configuration_changed} =
               SSO.complete_callback(transaction, valid_claims(), nil, %{
                 audit_data(context.admin)
                 | user: nil
               })
    end

    test "logs in by connection, issuer, and subject after linking", context do
      connection = configured_and_tested_connection(context)

      assert {:ok, _connection} =
               SSO.enable(context.organization, audit: audit_data(context.admin))

      insert(:organization_sso_identity,
        connection: connection,
        organization: context.organization,
        user: context.admin
      )

      stub_authorization_uri()

      assert {:ok, transaction, _uri} =
               SSO.start_login(
                 context.organization,
                 "/dashboard/orgs/#{context.organization.name}/packages",
                 "https://hex.pm/sso/callback"
               )

      transaction = SSO.get_transaction_by_state(transaction.raw_state)
      email = List.first(context.admin.emails).email
      return_path = "/dashboard/orgs/#{context.organization.name}/packages"

      assert {:ok, {:login, user, false, ^email, ^return_path}} =
               SSO.complete_callback(transaction, valid_claims(email), nil, %{
                 audit_data(context.admin)
                 | user: nil
               })

      assert user.id == context.admin.id
    end

    test "member removal purges the organization-scoped identity", context do
      connection = configured_and_tested_connection(context)
      member = insert(:user)
      insert(:organization_user, organization: context.organization, user: member, role: "read")

      identity =
        insert(:organization_sso_identity,
          connection: connection,
          organization: context.organization,
          user: member
        )

      linked_notification =
        insert(:organization_sso_notification,
          connection: connection,
          user: member,
          kind: "identity_linked"
        )

      mismatch_notification =
        insert(:organization_sso_notification,
          connection: connection,
          user: member,
          kind: "email_mismatch",
          provider_email: "renamed@identity.example.com"
        )

      assert :ok =
               Organizations.remove_member(context.organization, member,
                 audit: audit_data(context.admin)
               )

      refute Repo.get(Identity, identity.id)
      refute Organizations.access?(context.organization, member, "read")
      refute Repo.get(Notification, linked_notification.id)
      refute Repo.get(Notification, mismatch_notification.id)
      assert %Notification{kind: "identity_unlinked"} = Repo.one!(Notification)
    end

    test "member removal invalidates a proved pending link", context do
      configured_and_tested_connection(context)

      assert {:ok, _connection} =
               SSO.enable(context.organization, audit: audit_data(context.admin))

      member = insert(:user)
      insert(:organization_user, organization: context.organization, user: member, role: "read")
      stub_authorization_uri()

      assert {:ok, transaction, _uri} =
               SSO.start_login(context.organization, nil, "https://hex.pm/sso/callback")

      transaction = SSO.get_transaction_by_state(transaction.raw_state)

      assert {:ok, {:link, transaction_id, link_token, _return_path}} =
               SSO.complete_callback(transaction, valid_claims(), nil, %{
                 audit_data(context.admin)
                 | user: nil
               })

      assert {:ok, _transaction} = SSO.prove_link(transaction_id, link_token, member)

      assert :ok =
               Organizations.remove_member(context.organization, member,
                 audit: audit_data(context.admin)
               )

      refute Repo.get(SSO.Transaction, transaction_id)
      assert Repo.all(Identity) == []
    end

    test "concurrent link completion and member removal cannot leave identity data", context do
      configured_and_tested_connection(context)

      assert {:ok, _connection} =
               SSO.enable(context.organization, audit: audit_data(context.admin))

      member = insert(:user)
      insert(:organization_user, organization: context.organization, user: member, role: "read")
      stub_authorization_uri()

      assert {:ok, transaction, _uri} =
               SSO.start_login(context.organization, nil, "https://hex.pm/sso/callback")

      transaction = SSO.get_transaction_by_state(transaction.raw_state)

      assert {:ok, {:link, transaction_id, link_token, _return_path}} =
               SSO.complete_callback(transaction, valid_claims(), nil, %{
                 audit_data(context.admin)
                 | user: nil
               })

      assert {:ok, _transaction} = SSO.prove_link(transaction_id, link_token, member)

      parent = self()

      link_task =
        Task.async(fn ->
          send(parent, {:ready, self()})

          receive do
            :go ->
              SSO.complete_link(
                transaction_id,
                link_token,
                member,
                audit_data(member)
              )
          end
        end)

      removal_task =
        Task.async(fn ->
          send(parent, {:ready, self()})

          receive do
            :go ->
              Organizations.remove_member(context.organization, member,
                audit: audit_data(context.admin)
              )
          end
        end)

      pids =
        for _task <- 1..2 do
          assert_receive {:ready, pid}
          pid
        end

      Enum.each(pids, &send(&1, :go))

      link_result = Task.await(link_task, 5_000)
      assert Task.await(removal_task, 5_000) == :ok
      assert match?({:ok, %Identity{}}, link_result) or match?({:error, _reason}, link_result)

      refute Organizations.access?(context.organization, member, "read")
      assert Repo.all(from(identity in Identity, where: identity.user_id == ^member.id)) == []
      refute Repo.get(SSO.Transaction, transaction_id)
    end

    test "a stale identity cannot log in after membership is removed", context do
      connection = configured_and_tested_connection(context)

      assert {:ok, _connection} =
               SSO.enable(context.organization, audit: audit_data(context.admin))

      identity =
        insert(:organization_sso_identity,
          connection: connection,
          organization: context.organization,
          user: context.admin
        )

      Repo.delete_all(
        from(organization_user in Hexpm.Accounts.OrganizationUser,
          where:
            organization_user.organization_id == ^context.organization.id and
              organization_user.user_id == ^context.admin.id
        )
      )

      stub_authorization_uri()

      assert {:ok, transaction, _uri} =
               SSO.start_login(context.organization, nil, "https://hex.pm/sso/callback")

      transaction = SSO.get_transaction_by_state(transaction.raw_state)

      assert {:error, :not_member} =
               SSO.complete_callback(transaction, valid_claims(), nil, %{
                 audit_data(context.admin)
                 | user: nil
               })

      refute Repo.get(Identity, identity.id)
      refute SSO.get_transaction_by_state(transaction.raw_state)

      assert [%{stage: "login", code: "not_member"}] = SSO.failures(connection)
    end
  end

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
                 SSO.start_login(context.organization, nil, "https://hex.pm/sso/callback")

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
                 SSO.complete_callback(transaction, claims, nil, %{
                   audit_data(context.admin)
                   | user: nil
                 })

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
