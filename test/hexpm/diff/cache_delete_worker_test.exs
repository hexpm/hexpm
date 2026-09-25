defmodule Hexpm.Diff.CacheDeleteWorkerTest do
  use Hexpm.DataCase, async: true
  use Oban.Testing, repo: Hexpm.RepoBase

  alias Hexpm.Diff.CacheDeleteWorker

  test "deletes the package's cached diffs" do
    Hexpm.Store.put(:diff_bucket, "repos/acme/metadata/foo-1.0.0-2.0.0-1.json", "{}", [])
    Hexpm.Store.put(:diff_bucket, "repos/acme/metadata/foobar-1.0.0-2.0.0-1.json", "{}", [])

    assert :ok = perform_job(CacheDeleteWorker, %{"repository" => "acme", "package" => "foo"})

    assert Enum.to_list(Hexpm.Store.list(:diff_bucket, "")) == [
             "repos/acme/metadata/foobar-1.0.0-2.0.0-1.json"
           ]
  end

  test "queues one job per package while one is waiting" do
    assert {:ok, _} = CacheDeleteWorker.enqueue("hexpm", "foo")
    assert {:ok, _} = CacheDeleteWorker.enqueue("hexpm", "foo")
    assert {:ok, _} = CacheDeleteWorker.enqueue("hexpm", "bar")

    assert length(all_enqueued(worker: CacheDeleteWorker)) == 2
  end
end
