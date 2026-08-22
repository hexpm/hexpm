defmodule Hexpm.Accounts.SSOConcurrencyTest do
  use Hexpm.DataCase
  import Hexpm.ConcurrencyCase

  alias Hexpm.Accounts.SSO
  alias Hexpm.Accounts.SSO.{Connection, Identity, OIDC, OrgSession}
  alias Hexpm.Emails
  alias Hexpm.Emails.Outbox
  alias Hexpm.Emails.{OutboxEntry, OutboxWorker}

  @redirect_uri "https://hex.pm/sso/callback"

  setup do
    advisory_locks = Application.fetch_env!(:hexpm, :skip_advisory_locks)
    organization_sso = Application.fetch_env!(:hexpm, :organization_sso)
    mailer = Application.fetch_env!(:hexpm, Emails.Mailer)

    Application.put_env(:hexpm, :skip_advisory_locks, false)

    on_exit(fn ->
      Application.put_env(:hexpm, :skip_advisory_locks, advisory_locks)
      Application.put_env(:hexpm, :organization_sso, organization_sso)
      Application.put_env(:hexpm, Emails.Mailer, mailer)
    end)

    :ok
  end

  test "two callbacks for one transaction produce one login and one refusal" do
    committed(fn context ->
      link_identity(context, context.member)
      user_session = browser_session(context.member)
      transaction = start_transaction(context, context.member)

      results =
        race(2, fn ->
          SSO.complete_callback(
            transaction,
            valid_claims(),
            context.member,
            user_session.id,
            audit_data(context.member)
          )
        end)

      assert Enum.count(results, &match?({:ok, {:login, _user, _session, _return}}, &1)) == 1
      assert Enum.count(results, &match?({:error, :transaction_already_used}, &1)) == 1
      assert committed_count(context, OrgSession) == 1
    end)
  end

  test "two callbacks for one browser session leave one organization access session" do
    committed(fn context ->
      link_identity(context, context.member)
      user_session = browser_session(context.member)
      first = start_transaction(context, context.member)
      second = start_transaction(context, context.member)

      results =
        race([first, second], fn transaction ->
          SSO.complete_callback(
            transaction,
            valid_claims(),
            context.member,
            user_session.id,
            audit_data(context.member)
          )
        end)

      assert Enum.count(results, &match?({:ok, {:login, _user, _session, _return}}, &1)) == 2
      assert committed_count(context, OrgSession) == 1
    end)
  end

  test "two accounts adopting one subject leave a single identity" do
    committed(fn context ->
      first = pending_link(context, context.member)
      second = pending_link(context, context.other_member)

      results =
        race([{first, context.member}, {second, context.other_member}], fn {link, user} ->
          {transaction_id, link_token} = link

          SSO.complete_link(
            transaction_id,
            link_token,
            user,
            browser_session(user).id,
            audit_data(user)
          )
        end)

      assert Enum.count(results, &match?({:ok, {%Identity{}, %OrgSession{}}}, &1)) == 1
      assert Enum.count(results, &match?({:error, {:identity_conflict, _changeset}}, &1)) == 1
      assert committed_count(context, Identity) == 1
    end)
  end

  test "abandoning and completing the same login never deadlock" do
    committed(fn context ->
      link_identity(context, context.member)
      user_session = browser_session(context.member)

      for _round <- 1..4 do
        transactions =
          for _pair <- 1..5, do: start_transaction(context, context.member)

        # A deadlock raises out of the task, so reaching the assertion at all is
        # the result. Taking the transaction before the connection in one of the
        # two paths reproduces it here within a round or two.
        results =
          transactions
          |> Enum.flat_map(fn transaction ->
            [
              fn ->
                SSO.complete_callback(
                  transaction,
                  valid_claims(),
                  context.member,
                  user_session.id,
                  audit_data(context.member)
                )
              end,
              fn -> SSO.abandon_login(transaction, :callback, :account_session_required) end
            ]
          end)
          |> race()

        assert length(results) == 10
      end
    end)
  end

  # This does NOT prove the lock ordering. Both racers run the same distinct
  # query over the same two group keys, so they compute the same order whether
  # or not it is sorted, and no ABBA pair can form. Producing one on demand
  # needs the planner to disagree with itself between two queries, which is not
  # something a test can pin down. What this does cover is that two concurrent
  # scope cancellations over shared groups both complete and each deletes only
  # its own rows, which is worth having and is why it stays.
  test "an administrator demoted while a connection setting waits for the lock cannot land it" do
    committed(fn context ->
      parent = self()

      holder =
        unboxed_task(fn ->
          Hexpm.RepoBase.transaction(fn ->
            Hexpm.RepoBase.one!(
              from(connection in Connection,
                where: connection.id == ^context.connection.id,
                lock: "FOR UPDATE"
              )
            )

            send(parent, {:locked, self()})
            assert_receive :release, 15_000
          end)
        end)

      assert_receive {:locked, _pid}, 15_000

      writer =
        unboxed_task(fn ->
          SSO.configure_enforcement(context.organization, %{"enforcement_mode" => "pilot"},
            audit: audit_data(context.admin)
          )
        end)

      # The write has to be waiting on the row lock before the demotion lands,
      # or the check before the transaction is what refuses it and the one
      # under the lock is never reached.
      assert await_lock_wait() == :waiting

      Hexpm.RepoBase.update_all(
        from(member in Hexpm.Accounts.OrganizationUser,
          where: member.organization_id == ^context.organization.id,
          where: member.user_id == ^context.admin.id
        ),
        set: [role: "write"]
      )

      send(holder.pid, :release)
      assert {:ok, _result} = Task.await(holder, 15_000)
      assert Task.await(writer, 15_000) == {:error, :admin_required}

      assert Hexpm.RepoBase.get!(Connection, context.connection.id).enforcement_mode == "optional"
    end)
  end

  # Postgres is the only thing that knows the other transaction is blocked, so
  # ask it rather than sleeping for a while and hoping.
  defp await_lock_wait do
    Enum.reduce_while(1..300, :timeout, fn _attempt, _acc ->
      %{rows: [[waiting]]} =
        Ecto.Adapters.SQL.query!(
          Hexpm.RepoBase,
          """
          SELECT count(*) FROM pg_locks locks
          JOIN pg_stat_activity backends ON backends.pid = locks.pid
          WHERE NOT locks.granted AND backends.datname = current_database()
          """
        )

      if waiting > 0 do
        {:halt, :waiting}
      else
        Process.sleep(10)
        {:cont, :timeout}
      end
    end)
  end

  test "concurrent scope cancellations over shared groups each delete their own rows" do
    committed(fn context ->
      groups = ["sso:#{context.connection.id}:b", "sso:#{context.connection.id}:a"]
      scopes = ["sso:user:#{context.member.id}", "sso:user:#{context.other_member.id}"]

      for _round <- 1..4 do
        for scope <- scopes, group <- groups do
          insert(:email_outbox_entry,
            category: "sso.identity_linked",
            group_key: group,
            scope_key: scope
          )
        end

        results =
          race(scopes, fn scope ->
            Hexpm.RepoBase.transaction(fn ->
              Outbox.cancel!(scope_key: scope, categories: ["sso.identity_linked"])
            end)
          end)

        assert Enum.all?(results, &match?({:ok, 2}, &1))
        assert committed_count(context, OutboxEntry) == 0
      end
    end)
  end

  test "cancelling a notification does not wait for one that is being delivered" do
    committed(fn context ->
      link_identity(context, context.member)

      entry =
        insert(:email_outbox_entry,
          category: "sso.identity_linked",
          group_key: "sso:#{context.connection.id}:#{context.member.id}",
          scope_key: "sso:user:#{context.member.id}"
        )

      Application.put_env(
        :hexpm,
        Emails.Mailer,
        Application.fetch_env!(:hexpm, Emails.Mailer)
        |> Keyword.put(:adapter, Emails.BlockingAdapter)
        |> Keyword.put(:test_pid, self())
      )

      delivery =
        unboxed_task(fn ->
          OutboxWorker.perform(%Oban.Job{
            args: %{"outbox_entry_id" => entry.id},
            attempt: 1,
            max_attempts: 10
          })
        end)

      assert_receive {:delivery_started, _email, delivering_pid}, 5_000

      unlink =
        unboxed_task(fn ->
          SSO.unlink_identity(context.organization, context.member,
            audit: audit_data(context.admin)
          )
        end)

      assert {:ok, %Identity{}} = Task.await(unlink, 2_000)
      assert Repo.get(OutboxEntry, entry.id)

      send(delivering_pid, :release)
      assert :ok = Task.await(delivery, 5_000)
      refute Repo.get(OutboxEntry, entry.id)
    end)
  end

  defp committed(fun), do: committed(&build_context/0, fun)

  defp build_context do
    organization = insert(:organization)
    admin = insert(:user)
    member = insert(:user)
    other_member = insert(:user)

    insert(:organization_user, organization: organization, user: admin, role: "admin")
    insert(:organization_user, organization: organization, user: member)
    insert(:organization_user, organization: organization, user: other_member)

    config = Application.fetch_env!(:hexpm, :organization_sso)

    Application.put_env(
      :hexpm,
      :organization_sso,
      Keyword.merge(config, mode: :beta, beta_organizations: [organization.name])
    )

    connection =
      insert(:organization_sso_connection,
        organization: organization,
        tested_at: DateTime.utc_now(),
        enabled_at: DateTime.utc_now()
      )

    %{
      organization: organization,
      admin: admin,
      member: member,
      other_member: other_member,
      connection: connection
    }
  end

  defp link_identity(context, user) do
    insert(:organization_sso_identity,
      connection: context.connection,
      organization: context.organization,
      user: user
    )
  end

  defp pending_link(context, user) do
    transaction = start_transaction(context, user)

    assert {:ok, {:link, transaction_id, link_token}} =
             SSO.complete_callback(
               transaction,
               valid_claims(),
               user,
               browser_session(user).id,
               audit_data(user)
             )

    {transaction_id, link_token}
  end

  defp start_transaction(context, user) do
    Mox.stub(OIDC.Mock, :authorization_uri, fn _connection,
                                               _transaction,
                                               _redirect_uri,
                                               _secret ->
      {:ok, "https://identity.example.com/authorize"}
    end)

    assert {:ok, transaction, _uri} =
             SSO.start_login(context.organization, user, nil, @redirect_uri)

    SSO.get_transaction_by_state(transaction.raw_state)
  end

  defp browser_session(user) do
    {:ok, session, _token} =
      Hexpm.UserSessions.create_browser_session(user, audit: audit_data(user))

    session
  end

  defp valid_claims do
    %{
      issuer: "https://identity.example.com/oauth2/default",
      subject: "00u123",
      email: "member@example.com",
      jwks_document: nil
    }
  end
end
