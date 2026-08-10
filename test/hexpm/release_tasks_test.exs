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
  end
end
