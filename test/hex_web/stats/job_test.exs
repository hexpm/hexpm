defmodule HexWeb.Stats.JobTest do
  use HexWebTest.Case

  alias HexWeb.User
  alias HexWeb.Package
  alias HexWeb.Release

  @moduletag :integration

  setup do
    {:ok, user} = User.create(%{username: "eric", email: "eric@mail.com", password: "eric"}, true)
    {:ok, foo} = Package.create(user, pkg_meta(%{name: "foo", description: "Foo"}))
    {:ok, bar} = Package.create(user, pkg_meta(%{name: "bar", description: "Bar"}))
    {:ok, other} = Package.create(user, pkg_meta(%{name: "other", description: "Other"}))

    {:ok, _} = Release.create(foo, rel_meta(%{version: "0.0.1", app: "foo"}), "")
    {:ok, _} = Release.create(foo, rel_meta(%{version: "0.0.2", app: "foo"}), "")
    {:ok, _} = Release.create(foo, rel_meta(%{version: "0.1.0", app: "foo"}), "")
    {:ok, _} = Release.create(bar, rel_meta(%{version: "0.0.1", app: "bar"}), "")
    {:ok, _} = Release.create(bar, rel_meta(%{version: "0.0.2", app: "bar"}), "")
    {:ok, _} = Release.create(bar, rel_meta(%{version: "0.0.3-rc.1", app: "bar"}), "")
    {:ok, _} = Release.create(other, rel_meta(%{version: "0.0.1", app: "other"}), "")

    :ok
  end

  test "counts all downloads" do
    buckets = Application.get_env(:hex_web, :logs_buckets)
    if buckets do
      [[bucket, region]] = buckets
      Application.put_env(:hex_web, :store, HexWeb.Store.S3)
    else
      buckets = [[bucket = nil, region = nil]]
    end

    path     = Path.join([__DIR__, "..", "..", "fixtures"])
    logfile1 = File.read!(Path.join(path, "s3_logs_1.txt"))
    logfile2 = File.read!(Path.join(path, "s3_logs_2.txt"))
    store    = Application.get_env(:hex_web, :store)

    store.put_logs(region, bucket, "hex/2013-11-01-21-32-16-E568B2907131C0C0", logfile1)
    store.put_logs(region, bucket, "hex/2013-11-02-21-32-17-E568B2907131C0C0", logfile1)
    store.put_logs(region, bucket, "hex/2013-11-03-21-32-18-E568B2907131C0C0", logfile1)
    store.put_logs(region, bucket, "hex/2013-11-01-21-32-19-E568B2907131C0C0", logfile2)

    HexWeb.Stats.Job.run({2013, 11, 1}, buckets)

    rel1 = Release.get(Package.get("foo"), "0.0.1")
    rel2 = Release.get(Package.get("foo"), "0.0.2")
    rel3 = Release.get(Package.get("bar"), "0.0.2")
    rel4 = Release.get(Package.get("bar"), "0.0.3-rc.1")

    downloads = HexWeb.Repo.all(HexWeb.Stats.Download)
    assert length(downloads) == 4

    assert Enum.find(downloads, &(&1.release_id == rel1.id)).downloads == 5
    assert Enum.find(downloads, &(&1.release_id == rel2.id)).downloads == 2
    assert Enum.find(downloads, &(&1.release_id == rel3.id)).downloads == 2
    assert Enum.find(downloads, &(&1.release_id == rel4.id)).downloads == 1
  after
    Application.put_env(:hex_web, :store, HexWeb.Store.Local)
  end
end
