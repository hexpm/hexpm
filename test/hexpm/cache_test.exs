defmodule Hexpm.CacheTest do
  use Hexpm.DataCase
  alias Ecto.Adapters.SQL.Sandbox
  alias Hexpm.{Cache, RepoBase}

  setup do
    Sandbox.mode(RepoBase, {:shared, self()})
    :ok
  end

  test "populates release_count and last_download_day" do
    package = insert(:package)
    release = insert(:release, package: package)
    insert(:download, package: package, release: release, downloads: 1, day: ~D[2024-01-15])

    {:ok, pid} = Cache.start_link(name: :cache_test_populate, interval: 60_000)
    on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)

    assert Cache.release_count(:cache_test_populate) == 1
    assert Cache.last_download_day(:cache_test_populate) == ~D[2024-01-15]
  end

  test "refresh re-reads values" do
    {:ok, pid} = Cache.start_link(name: :cache_test_refresh, interval: 60_000)
    on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)

    assert Cache.release_count(:cache_test_refresh) == 0
    assert Cache.last_download_day(:cache_test_refresh) == nil

    package = insert(:package)
    release = insert(:release, package: package)
    insert(:download, package: package, release: release, downloads: 1, day: ~D[2024-02-20])

    :ok = Cache.refresh(:cache_test_refresh)

    assert Cache.release_count(:cache_test_refresh) == 1
    assert Cache.last_download_day(:cache_test_refresh) == ~D[2024-02-20]
  end
end
