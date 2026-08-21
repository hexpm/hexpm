defmodule Hexpm.Repository.RegistryWorkerLockTest do
  use Hexpm.DataCase, async: false
  use Oban.Testing, repo: Hexpm.RepoBase

  alias Hexpm.Repository.{RegistryWorker, Repository}

  setup do
    previous = Application.get_env(:hexpm, :skip_advisory_locks)
    Application.put_env(:hexpm, :skip_advisory_locks, false)
    on_exit(fn -> Application.put_env(:hexpm, :skip_advisory_locks, previous) end)

    package = insert(:package) |> Hexpm.Repo.preload(:repository)
    insert(:release, package: package, version: "0.0.1")
    other = insert(:package) |> Hexpm.Repo.preload(:repository)
    insert(:release, package: other, version: "0.0.1")
    %{package: package, other: other}
  end

  # Holds `sql` in a transaction on its own connection until released.
  defp hold(sql, params) do
    parent = self()

    holder =
      spawn_link(fn ->
        :ok = Ecto.Adapters.SQL.Sandbox.checkout(Hexpm.RepoBase)
        Hexpm.RepoBase.query!(sql, params)
        send(parent, :locked)

        receive do
          :release -> :ok
        end
      end)

    assert_receive :locked
    holder
  end

  defp hold_repository(mode) do
    function =
      case mode do
        :full -> "pg_advisory_xact_lock"
        :shared -> "pg_advisory_xact_lock_shared"
      end

    key = Hexpm.RepoBase.advisory_lock_key(:registry)
    hold("SELECT #{function}($1, $2)", [key, Repository.hexpm().id])
  end

  defp hold_object(object) do
    key = Hexpm.RepoBase.advisory_lock_key(:registry)
    object_key = Hexpm.RepoBase.advisory_lock_key(:registry_object)

    hold(
      "SELECT pg_advisory_xact_lock_shared($1, $2), pg_advisory_xact_lock($3, $4)",
      [key, Repository.hexpm().id, object_key, RegistryWorker.object_lock_key(object)]
    )
  end

  defp package_args(package), do: %{"type" => "package", "package_id" => package.id}
  defp package_object(package), do: {package.repository_id, "packages/#{package.name}"}
  defp repository_args, do: %{"type" => "repository", "repository_id" => Repository.hexpm().id}
  defp full_args, do: %{"type" => "full", "repository_id" => Repository.hexpm().id}

  test "snoozes while a full build holds the repository", %{package: package} do
    holder = hold_repository(:full)

    assert perform_job(RegistryWorker, package_args(package)) == {:snooze, 30}
    refute Hexpm.Store.get(:repo_bucket, "packages/#{package.name}", [])

    send(holder, :release)
  end

  test "a full build snoozes while a package build holds the repository shared" do
    holder = hold_repository(:shared)
    assert perform_job(RegistryWorker, full_args()) == {:snooze, 30}
    send(holder, :release)
  end

  test "builds beside another package build of a different package", %{
    package: package,
    other: other
  } do
    holder = hold_object(package_object(other))

    assert perform_job(RegistryWorker, package_args(package)) == :ok
    assert Hexpm.Store.get(:repo_bucket, "packages/#{package.name}", [])

    send(holder, :release)
  end

  test "snoozes while another build holds the same object", %{package: package} do
    holder = hold_object(package_object(package))

    assert perform_job(RegistryWorker, package_args(package)) == {:snooze, 30}
    refute Hexpm.Store.get(:repo_bucket, "packages/#{package.name}", [])

    send(holder, :release)
  end

  test "an index build runs beside a package build", %{package: package} do
    holder = hold_object(package_object(package))
    assert perform_job(RegistryWorker, repository_args()) == :ok
    send(holder, :release)
  end

  test "an index build snoozes while another index build runs" do
    holder = hold_object({Repository.hexpm().id, :index})
    assert perform_job(RegistryWorker, repository_args()) == {:snooze, 30}
    send(holder, :release)
  end

  test "a snooze rolls the cancellation of queued siblings back", %{package: package} do
    {:ok, sibling} = RegistryWorker.enqueue_package(package)
    {:ok, job} = RegistryWorker.enqueue_package(package)
    holder = hold_object(package_object(package))

    assert RegistryWorker.perform(Repo.get!(Oban.Job, job.id)) == {:snooze, 30}
    assert Repo.get!(Oban.Job, sibling.id).state == "available"

    send(holder, :release)
  end

  test "builds once the locks are free", %{package: package} do
    assert perform_job(RegistryWorker, package_args(package)) == :ok
    assert Hexpm.Store.get(:repo_bucket, "packages/#{package.name}", [])
  end
end
