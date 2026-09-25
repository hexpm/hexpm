defmodule Hexpm.StoreFailureTest do
  # Swaps a bucket's store for one that fails, which is global config.
  use Hexpm.DataCase, async: false
  use Oban.Testing, repo: Hexpm.RepoBase

  alias Hexpm.{AdminTasks, OrphanedObjects}

  defmodule FailingStore do
    @behaviour Hexpm.Store.Behaviour

    def list_objects(bucket, prefix) do
      if Process.get(:fail) == :list, do: raise("store down")
      Hexpm.Store.Memory.list_objects(bucket, prefix)
    end

    def delete_many(bucket, keys) do
      if Process.get(:fail) == :delete, do: raise("store down")
      Hexpm.Store.Memory.delete_many(bucket, keys)
    end

    defdelegate get(bucket, key, opts), to: Hexpm.Store.Memory
    defdelegate size(bucket, key), to: Hexpm.Store.Memory
    defdelegate stream(bucket, key), to: Hexpm.Store.Memory
    defdelegate get_to_file(bucket, key, path, opts), to: Hexpm.Store.Memory
    defdelegate put(bucket, key, body, opts), to: Hexpm.Store.Memory
    defdelegate put_file(bucket, key, path, opts), to: Hexpm.Store.Memory
    defdelegate delete(bucket, key), to: Hexpm.Store.Memory
  end

  test "remove_release queues the registry rebuild before touching the diff cache" do
    package = insert(:package)
    insert(:release, package: package, version: "1.0.0")
    insert(:release, package: package, version: "2.0.0")
    app_env(:hexpm, :diff_bucket, {FailingStore, "diff_bucket"})
    Process.put(:fail, :list)

    assert_raise RuntimeError, "store down", fn ->
      AdminTasks.remove_release("hexpm", package.name, "1.0.0")
    end

    assert length(all_enqueued(worker: Hexpm.Repository.RegistryWorker)) == 2
  end

  test "the sweep records a gone repository for the backup before deleting its objects" do
    insert(:package, name: "hex", repository_id: 1)
    Hexpm.Store.put(:repo_bucket, "repos/gone/names", "DATA", [])
    app_env(:hexpm, :repo_bucket, {FailingStore, "repo_bucket"})
    Process.put(:fail, :delete)

    assert_raise RuntimeError, "store down", fn ->
      OrphanedObjects.delete(buckets: [:repo_bucket], older_than: 0)
    end

    assert Hexpm.Store.get(:deletions_bucket, "organizations/gone", [])
  end
end
