defmodule HexWeb.RegistryBuilderTest do
  use HexWebTest.Case

  alias HexWeb.User
  alias HexWeb.Package
  alias HexWeb.Release
  alias HexWeb.Install
  alias HexWeb.RegistryBuilder

  @ets_table :hex_registry

  setup do
    {:ok, user} = User.create("eric", "eric@mail.com", "eric", true)
    {:ok, _} = Package.create("postgrex", user, %{})
    {:ok, _} = Package.create("decimal", user, %{})
    {:ok, _} = Package.create("ex_doc", user, %{})
    {:ok, _} = Install.create("0.0.1", ["0.13.0-dev"])
    {:ok, _} = Install.create("0.1.0", ["0.13.1-dev", "0.13.1"])
    :ok
  end

  defp open_table do
    {:ok, tid} = :ets.file2tab('tmp/registry.ets')
    tid
  end

  defp close_table(tid) do
    :ets.delete(tid)
  end

  test "registry is versioned" do
    RegistryBuilder.rebuild()
    tid = open_table()

    try do
      assert [{:"$$version$$", 3}] = :ets.lookup(tid, :"$$version$$")
    after
      close_table(tid)
    end
  end

  test "registry includes installs" do
    RegistryBuilder.rebuild()
    tid = open_table()

    try do
      assert [{:"$$installs$$", installs}] = :ets.lookup(tid, :"$$installs$$")
      assert [{"0.0.1", "0.13.0-dev"}, {"0.1.0", "0.13.1-dev"}] = installs

      assert [{:"$$installs2$$", installs}] = :ets.lookup(tid, :"$$installs2$$")
      assert [{"0.0.1", ["0.13.0-dev"]}, {"0.1.0", ["0.13.1-dev", "0.13.1"]}] = installs
    after
      close_table(tid)
    end
  end

  test "registry is in correct format" do
    postgrex = Package.get("postgrex")
    decimal = Package.get("decimal")

    Release.create(decimal, "0.0.1", "decimal", [], "")
    Release.create(decimal, "0.0.2", "decimal", [{"ex_doc", "0.0.0"}], "")
    Release.create(postgrex, "0.0.2", "postgrex", [{"decimal", "~> 0.0.1"}, {"ex_doc", "0.1.0"}], "")

    RegistryBuilder.rebuild()
    tid = open_table()

    try do
      assert length(:ets.match_object(tid, :_)) == 8

      assert [ {"decimal", [["0.0.1", "0.0.2"]]} ] = :ets.lookup(tid, "decimal")

      assert [ {{"decimal", "0.0.1"}, [[], ""]} ] =
             :ets.lookup(tid, {"decimal", "0.0.1"})

      assert [{"postgrex", [["0.0.2"]]}] =
             :ets.lookup(tid, "postgrex")

      reqs = :ets.lookup(tid, {"postgrex", "0.0.2"}) |> List.first |> elem(1) |> List.first
      assert length(reqs) == 2
      assert Enum.find(reqs, &(&1 == ["decimal", "~> 0.0.1", false, "decimal"]))
      assert Enum.find(reqs, &(&1 == ["ex_doc", "0.1.0", false, "ex_doc"]))

      assert [] = :ets.lookup(tid, "ex_doc")
    after
      close_table(tid)
    end
  end

  test "building is blocking" do
    postgrex = Package.get("postgrex")
    decimal = Package.get("decimal")

    Release.create(decimal, "0.0.1", "decimal", [], "")
    Release.create(decimal, "0.0.2", "decimal", [{"ex_doc", "0.0.0"}], "")
    Release.create(postgrex, "0.0.2", "postgrex", [{"decimal", "~> 0.0.1"}, {"ex_doc", "0.1.0"}], "")

    pid = self

    Task.start_link(fn ->
      RegistryBuilder.rebuild
      send pid, :done
    end)
    Task.start_link(fn ->
      RegistryBuilder.rebuild
      send pid, :done
    end)

    RegistryBuilder.rebuild

    receive do: (:done -> :ok)
    receive do: (:done -> :ok)

    tid = open_table()
    close_table(tid)
  end
end
