defmodule Hexpm.OrphanedObjectsRaceTest do
  use Hexpm.DataCase, async: false

  alias Hexpm.OrphanedObjects

  # Reports every object as written now when it is asked for one object by its
  # exact key, which is what `Hexpm.Store.object/2` does, and reports the store
  # timestamps for a prefix listing. That is the shape of a version republished
  # after the listing: the key is the one that was listed, the object under it
  # is not.
  defmodule RewritingStore do
    @behaviour Hexpm.Store.Behaviour

    defdelegate get(bucket, key, opts), to: Hexpm.Store.Memory
    defdelegate size(bucket, key), to: Hexpm.Store.Memory
    defdelegate stream(bucket, key), to: Hexpm.Store.Memory
    defdelegate get_to_file(bucket, key, path, opts), to: Hexpm.Store.Memory
    defdelegate put(bucket, key, body, opts), to: Hexpm.Store.Memory
    defdelegate put_file(bucket, key, path, opts), to: Hexpm.Store.Memory
    defdelegate delete(bucket, key), to: Hexpm.Store.Memory
    defdelegate delete_many(bucket, keys), to: Hexpm.Store.Memory

    def list_objects(bucket, prefix) do
      objects = Hexpm.Store.Memory.list_objects(bucket, prefix)

      if Enum.any?(objects, &(&1.key == prefix)) do
        Enum.map(objects, &%{&1 | last_modified: DateTime.utc_now()})
      else
        objects
      end
    end
  end

  setup do
    original = Application.get_env(:hexpm, :repo_bucket)
    Application.put_env(:hexpm, :repo_bucket, {RewritingStore, "repo_bucket"})
    on_exit(fn -> Application.put_env(:hexpm, :repo_bucket, original) end)
    :ok
  end

  test "leaves an orphan that was written again after the listing" do
    package = insert(:package)
    insert(:release, package: package, version: "1.0.0")

    Hexpm.Store.Memory.written_at(DateTime.add(DateTime.utc_now(), -30, :day))
    Hexpm.Store.put(:repo_bucket, "tarballs/#{package.name}-9.9.9.tar", "DATA", [])

    assert %{orphaned: 1, deleted: 0, rewritten: 1} =
             OrphanedObjects.delete(buckets: [:repo_bucket], older_than: 7)[:repo_bucket]

    assert Hexpm.Store.get(:repo_bucket, "tarballs/#{package.name}-9.9.9.tar", []) == "DATA"
  end

  test "deletes an orphan that has not moved since the listing" do
    package = insert(:package)
    insert(:release, package: package, version: "1.0.0")

    written_at = DateTime.add(DateTime.utc_now(), -30, :day)
    Hexpm.Store.Memory.written_at(written_at)
    Hexpm.Store.put(:repo_bucket, "tarballs/#{package.name}-9.9.9.tar", "DATA", [])

    Application.put_env(:hexpm, :repo_bucket, {Hexpm.Store.Memory, "repo_bucket"})

    assert %{orphaned: 1, deleted: 1, rewritten: 0} =
             OrphanedObjects.delete(buckets: [:repo_bucket], older_than: 7)[:repo_bucket]

    refute Hexpm.Store.get(:repo_bucket, "tarballs/#{package.name}-9.9.9.tar", [])
  end
end
