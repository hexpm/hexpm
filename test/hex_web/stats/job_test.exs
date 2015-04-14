defmodule HexWeb.Stats.JobTest do
  use HexWebTest.Case

  alias HexWeb.User
  alias HexWeb.Package
  alias HexWeb.Release

  @moduletag :integration

  setup do
    {:ok, user} = User.create(%{username: "eric", email: "eric@mail.com", password: "eric"}, true)
    {:ok, foo} = Package.create(user, %{name: "foo", meta: %{}})
    {:ok, bar} = Package.create(user, %{name: "bar", meta: %{}})
    {:ok, other} = Package.create(user, %{name: "other", meta: %{}})

    {:ok, _} = Release.create(foo, %{version: "0.0.1", app: "foo", requirements: %{}}, "")
    {:ok, _} = Release.create(foo, %{version: "0.0.2", app: "foo", requirements: %{}}, "")
    {:ok, _} = Release.create(foo, %{version: "0.1.0", app: "foo", requirements: %{}}, "")
    {:ok, _} = Release.create(bar, %{version: "0.0.1", app: "bar", requirements: %{}}, "")
    {:ok, _} = Release.create(bar, %{version: "0.0.2", app: "bar", requirements: %{}}, "")
    {:ok, _} = Release.create(other, %{version: "0.0.1", app: "other", requirements: %{}}, "")

    :ok
  end

  test "counts all downloads" do
    path     = Path.join([__DIR__, "..", "..", "fixtures"])
    logfile1 = File.read!(Path.join(path, "s3_logs_1.txt"))
    logfile2 = File.read!(Path.join(path, "s3_logs_2.txt"))
    store    = Application.get_env(:hex_web, :store)

    store.put_logs("hex/2013-11-01-21-32-16-E568B2907131C0C0", logfile1)
    store.put_logs("hex/2013-11-02-21-32-17-E568B2907131C0C0", logfile1)
    store.put_logs("hex/2013-11-03-21-32-18-E568B2907131C0C0", logfile1)
    store.put_logs("hex/2013-11-01-21-32-19-E568B2907131C0C0", logfile2)

    HexWeb.Stats.Job.run({2013, 11, 1})

    rel1 = Release.get(Package.get("foo"), "0.0.1")
    rel2 = Release.get(Package.get("foo"), "0.0.2")
    rel3 = Release.get(Package.get("bar"), "0.0.2")

    downloads = HexWeb.Repo.all(HexWeb.Stats.Download)
    assert length(downloads) == 3

    assert Enum.find(downloads, &(&1.release_id == rel1.id)).downloads == 5
    assert Enum.find(downloads, &(&1.release_id == rel2.id)).downloads == 2
    assert Enum.find(downloads, &(&1.release_id == rel3.id)).downloads == 2
  end
end
