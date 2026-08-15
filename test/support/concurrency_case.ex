defmodule Hexpm.ConcurrencyCase do
  @moduledoc """
  Helpers for tests that have to prove a lock works.

  The sandbox hands every process the same connection, so a test written against
  it cannot tell a lock that works from a lock that is never contended. Tests
  using these run unboxed on real connections and clean up after themselves.

  Import this alongside `use Hexpm.DataCase`.
  """

  import ExUnit.Assertions
  import ExUnit.Callbacks, only: [on_exit: 1]
  import Ecto.Query, only: [from: 2]

  alias Ecto.Adapters.SQL.Sandbox
  alias Hexpm.Accounts.{AuditLog, Email, Organization, OrganizationUser, User}
  alias Hexpm.Accounts.SSO.{Connection, Failure, Identity, OrgSession}
  alias Hexpm.Accounts.SSO.Transaction, as: SSOTransaction
  alias Hexpm.Emails.OutboxEntry
  alias Hexpm.UserSession

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

  @doc """
  Runs `fun` unboxed with the context `build_context` returns, and deletes every
  row committed inside it afterwards.
  """
  def committed(build_context, fun)
      when is_function(build_context, 0) and is_function(fun, 1) do
    Sandbox.unboxed_run(Hexpm.RepoBase, fn ->
      high_water_marks =
        Map.new(@committed_schemas, fn schema ->
          {schema, Hexpm.RepoBase.aggregate(schema, :max, :id) || 0}
        end)

      # on_exit rather than try/after: race/1 links its tasks, so a task that
      # crashes on the regression these tests exist to catch kills the test
      # process outright and an after block never runs. The rows are committed,
      # so skipping cleanup once leaks them into every later run.
      on_exit(fn ->
        Sandbox.unboxed_run(Hexpm.RepoBase, fn -> delete_committed(high_water_marks) end)
      end)

      build_context.()
      |> Map.put(:high_water_marks, high_water_marks)
      |> fun.()
    end)
  end

  defp delete_committed(high_water_marks) do
    # users and organizations reference each other, so one side has to let go
    # before either can be deleted.
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

  @doc """
  Counts only what this test committed. Counting the whole table would fail on
  any row a previous run leaked or a developer's database already holds.
  """
  def committed_count(context, schema) do
    Hexpm.RepoBase.aggregate(
      from(row in schema, where: row.id > ^Map.fetch!(context.high_water_marks, schema)),
      :count
    )
  end

  @doc """
  Runs `fun` in a task holding its own connection, which is the whole point: two
  sandbox processes share one and would serialize before reaching the lock.
  """
  def unboxed_task(fun) do
    Task.async(fn ->
      :ok = Sandbox.checkout(Hexpm.RepoBase, sandbox: false)
      fun.()
    end)
  end

  @doc """
  Starts every task, waits for all of them to hold a connection, then releases
  them together.
  """
  def race(count, fun) when is_integer(count) do
    fun |> List.duplicate(count) |> race()
  end

  def race(arguments, fun) when is_list(arguments) do
    arguments
    |> Enum.map(fn argument -> fn -> fun.(argument) end end)
    |> race()
  end

  def race(funs) when is_list(funs) do
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
      # Each task checks out a real connection before reporting ready, which the
      # 100ms default is not enough for on a loaded machine.
      assert_receive {:ready, pid}, 15_000
      pid
    end
    |> Enum.each(&send(&1, :go))

    Enum.map(tasks, &Task.await(&1, 15_000))
  end
end
