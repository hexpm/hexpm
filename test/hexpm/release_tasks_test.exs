defmodule Hexpm.ReleaseTasksTest do
  use Hexpm.DataCase, async: false

  alias Hexpm.ReleaseTasks

  defp locks_held() do
    key = Hexpm.RepoBase.advisory_lock_key(:migrate)

    %{rows: [[count]]} =
      Repo.query!(
        "SELECT count(*) FROM pg_locks WHERE locktype = 'advisory' AND classid = 0 AND objid = $1",
        [key]
      )

    count
  end

  defp lock_connections() do
    Repo.query!("SELECT pg_stat_clear_snapshot()", [])

    %{rows: [[count]]} =
      Repo.query!(
        """
        SELECT count(*) FROM pg_stat_activity
        WHERE datname = current_database()
          AND pid <> pg_backend_pid()
          AND query LIKE '%advisory_lock($1)'
        """,
        []
      )

    count
  end

  defp wait_until(fun, attempts \\ 100) do
    cond do
      fun.() ->
        :ok

      attempts == 0 ->
        flunk("condition not met")

      true ->
        Process.sleep(50)
        wait_until(fun, attempts - 1)
    end
  end

  defp create_index_concurrently() do
    opts =
      Keyword.take(Hexpm.RepoBase.config(), [:hostname, :port, :username, :password, :database])

    {:ok, conn} = Postgrex.start_link(opts)

    try do
      Postgrex.query!(conn, "DROP TABLE IF EXISTS migration_lock_test", [])
      Postgrex.query!(conn, "CREATE TABLE migration_lock_test (id integer)", [])

      Postgrex.query!(
        conn,
        "CREATE INDEX CONCURRENTLY migration_lock_test_id_index ON migration_lock_test (id)",
        []
      )

      Postgrex.query!(conn, "DROP TABLE migration_lock_test", [])
    after
      GenServer.stop(conn)
    end
  end

  describe "with_migration_lock/2" do
    test "holds the lock while the function runs" do
      assert locks_held() == 0

      ReleaseTasks.with_migration_lock(Hexpm.RepoBase, fn ->
        assert locks_held() == 1
      end)

      assert locks_held() == 0
    end

    test "releases the lock when the function raises" do
      assert_raise RuntimeError, "boom", fn ->
        ReleaseTasks.with_migration_lock(Hexpm.RepoBase, fn -> raise "boom" end)
      end

      assert locks_held() == 0
    end

    test "returns what the function returned" do
      assert ReleaseTasks.with_migration_lock(Hexpm.RepoBase, fn -> :migrated end) == :migrated
    end

    test "a second caller waits for the first to finish" do
      test = self()

      holder =
        Task.async(fn ->
          ReleaseTasks.with_migration_lock(Hexpm.RepoBase, fn ->
            send(test, :holding)
            receive do: (:release -> :ok)
          end)
        end)

      assert_receive :holding, 10_000

      waiter =
        Task.async(fn ->
          ReleaseTasks.with_migration_lock(Hexpm.RepoBase, fn -> send(test, :second_ran) end)
        end)

      refute_receive :second_ran, 200

      send(holder.pid, :release)
      Task.await(holder, 10_000)

      assert_receive :second_ran, 10_000
      Task.await(waiter, 10_000)
      assert locks_held() == 0
    end

    test "a waiting caller does not block CREATE INDEX CONCURRENTLY in the holder" do
      test = self()

      holder =
        Task.async(fn ->
          ReleaseTasks.with_migration_lock(Hexpm.RepoBase, fn ->
            send(test, :holding)
            receive do: (:create_index -> :ok)
            create_index_concurrently()
          end)
        end)

      assert_receive :holding, 10_000

      waiter =
        Task.async(fn ->
          ReleaseTasks.with_migration_lock(Hexpm.RepoBase, fn -> :ok end)
        end)

      wait_until(fn -> lock_connections() == 2 end)

      send(holder.pid, :create_index)
      Task.await(holder, 10_000)
      Task.await(waiter, 10_000)
      assert locks_held() == 0
    end
  end
end
