defmodule Hexpm.Repository.RegistryWorkerLockTest do
  use Hexpm.DataCase, async: false
  use Oban.Testing, repo: Hexpm.RepoBase

  alias Hexpm.Repository.RegistryWorker

  setup do
    Application.put_env(:hexpm, :skip_advisory_locks, false)
    on_exit(fn -> Application.put_env(:hexpm, :skip_advisory_locks, true) end)

    package = insert(:package) |> Hexpm.Repo.preload(:repository)
    insert(:release, package: package, version: "0.0.1")
    %{package: package}
  end

  test "snoozes instead of waiting when another build holds the registry lock", %{
    package: package
  } do
    parent = self()

    holder =
      spawn_link(fn ->
        :ok = Ecto.Adapters.SQL.Sandbox.checkout(Hexpm.RepoBase)
        key = Hexpm.RepoBase.advisory_lock_key(:registry)
        Hexpm.RepoBase.query!("SELECT pg_advisory_xact_lock($1)", [key])
        send(parent, :locked)

        receive do
          :release -> :ok
        end
      end)

    assert_receive :locked

    assert perform_job(RegistryWorker, %{"type" => "package", "package_id" => package.id}) ==
             {:snooze, 30}

    refute Hexpm.Store.get(:repo_bucket, "packages/#{package.name}", [])

    send(holder, :release)
  end

  test "builds once the lock is free", %{package: package} do
    assert perform_job(RegistryWorker, %{"type" => "package", "package_id" => package.id}) == :ok
    assert Hexpm.Store.get(:repo_bucket, "packages/#{package.name}", [])
  end
end
