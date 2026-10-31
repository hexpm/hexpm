defmodule Hexpm.RepoLockTest do
  use Hexpm.DataCase, async: false

  setup do
    app_env(:hexpm, :skip_advisory_locks, false)
  end

  test "a session lock holds its sub key against other connections until it's unlocked" do
    :ok = Hexpm.Repo.advisory_lock(:staged_publish, sub_key: 1)

    try do
      refute lock_elsewhere?(:staged_publish, 1)
      assert lock_elsewhere?(:staged_publish, 2)
    after
      :ok = Hexpm.Repo.advisory_unlock(:staged_publish, sub_key: 1)
    end

    assert lock_elsewhere?(:staged_publish, 1)
  end

  defp lock_elsewhere?(key, sub_key) do
    fn ->
      :ok = Ecto.Adapters.SQL.Sandbox.checkout(Hexpm.RepoBase)
      Hexpm.RepoBase.try_advisory_xact_lock?(key, sub_key: sub_key)
    end
    |> Task.async()
    |> Task.await()
  end
end
