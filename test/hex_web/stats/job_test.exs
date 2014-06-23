defmodule HexWeb.Stats.JobTest do
  use HexWebTest.Case

  alias HexWeb.User
  alias HexWeb.Package
  alias HexWeb.Release

  @moduletag :integration

  setup do
    {:ok, user} = User.create("eric", "eric@mail.com", "eric")
    {:ok, foo} = Package.create("foo", user, %{})
    {:ok, bar} = Package.create("bar", user, %{})
    {:ok, other} = Package.create("other", user, %{})

    {:ok, _} = Release.create(foo, "0.0.1", [], "")
    {:ok, _} = Release.create(foo, "0.0.2", [], "")
    {:ok, _} = Release.create(foo, "0.1.0", [], "")
    {:ok, _} = Release.create(bar, "0.0.1", [], "")
    {:ok, _} = Release.create(bar, "0.0.2", [], "")
    {:ok, _} = Release.create(other, "0.0.1", [], "")

    :ok
  end

  test "counts all downloads" do
    path = Path.join([__DIR__, "..", "..", "fixtures"])
    logfile1 = File.read!(Path.join(path, "s3_logs_1.txt"))
    logfile2 = File.read!(Path.join(path, "s3_logs_2.txt"))

    HexWeb.Config.store.put("logs/2013-11-01-21-32-16-E568B2907131C0C0", logfile1)
    HexWeb.Config.store.put("logs/2013-11-02-21-32-17-E568B2907131C0C0", logfile1)
    HexWeb.Config.store.put("logs/2013-11-03-21-32-18-E568B2907131C0C0", logfile1)
    HexWeb.Config.store.put("logs/2013-11-01-21-32-19-E568B2907131C0C0", logfile2)

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
