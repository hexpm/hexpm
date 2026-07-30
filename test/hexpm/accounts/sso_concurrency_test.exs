defmodule Hexpm.Accounts.SSOConcurrencyTest do
  # The sandbox hands every process the same connection, so a test written
  # against it cannot tell a lock that works from a lock that is never
  # contended. These run unboxed on real connections and clean up after
  # themselves.
  use Hexpm.DataCase

  alias Ecto.Adapters.SQL.Sandbox
  alias Hexpm.Accounts.{AuditLog, Email, Organization, OrganizationUser, SSO, User}
  alias Hexpm.Accounts.SSO.{Connection, Failure, Identity, OIDC, OrgSession}
  alias Hexpm.Accounts.SSO.Transaction, as: SSOTransaction
  alias Hexpm.Emails
  alias Hexpm.Emails.{OutboxEntry, OutboxWorker}
  alias Hexpm.UserSession

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
      assert Repo.aggregate(OrgSession, :count) == 1
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
      assert Repo.aggregate(OrgSession, :count) == 1
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
      assert Repo.aggregate(Identity, :count) == 1
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

  # Nothing here is rolled back, so the rows these tests commit have to be
  # removed by hand. Anything above the high-water mark is ours; the fixtures
  # test_helper.exs installs at id 1 sit below it and must survive.
  @committed_schemas [
    OrgSession,
    Identity,
    SSOTransaction,
    Failure,
    Connection,
    OutboxEntry,
    Oban.Job,
    AuditLog,
    UserSession,
    OrganizationUser,
    Organization,
    Email,
    User
  ]

  defp committed(fun) do
    Sandbox.unboxed_run(Hexpm.RepoBase, fn ->
      high_water_marks =
        Map.new(@committed_schemas, fn schema ->
          {schema, Hexpm.RepoBase.aggregate(schema, :max, :id) || 0}
        end)

      try do
        fun.(build_context())
      after
        # users and organizations reference each other, so one side has to let
        # go before either can be deleted.
        Hexpm.RepoBase.update_all(
          from(user in User, where: user.id > ^Map.fetch!(high_water_marks, User)),
          set: [organization_id: nil]
        )

        Enum.each(@committed_schemas, fn schema ->
          Hexpm.RepoBase.delete_all(
            from(row in schema, where: row.id > ^Map.fetch!(high_water_marks, schema))
          )
        end)
      end
    end)
  end

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

  # Each task takes its own connection, which is the whole point: two sandbox
  # processes share one and would serialize before reaching the lock.
  defp unboxed_task(fun) do
    Task.async(fn ->
      :ok = Sandbox.checkout(Hexpm.RepoBase, sandbox: false)
      fun.()
    end)
  end

  defp race(count, fun) when is_integer(count) do
    fun |> List.duplicate(count) |> race()
  end

  defp race(arguments, fun) when is_list(arguments) do
    arguments
    |> Enum.map(fn argument -> fn -> fun.(argument) end end)
    |> race()
  end

  defp race(funs) when is_list(funs) do
    parent = self()

    tasks =
      Enum.map(funs, fn fun ->
        unboxed_task(fn ->
          send(parent, {:ready, self()})

          receive do
            :go -> fun.()
          end
        end)
      end)

    for _task <- tasks do
      assert_receive {:ready, pid}
      pid
    end
    |> Enum.each(&send(&1, :go))

    Enum.map(tasks, &Task.await(&1, 15_000))
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

    assert {:ok, {:link, transaction_id, link_token, _return_path}} =
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
