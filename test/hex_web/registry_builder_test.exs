defmodule HexWeb.RegistryBuilderTest do
  use HexWebTest.Case

  alias HexWeb.User
  alias HexWeb.Package
  alias HexWeb.Release
  alias HexWeb.Install
  alias HexWeb.RegistryBuilder

  @ets_table :hex_registry

  setup do
    { :ok, _ } = RegistryBuilder.start_link
    { :ok, user } = User.create("eric", "eric@mail.com", "eric")
    { :ok, _ } = Package.create("postgrex", user, %{})
    { :ok, _ } = Package.create("decimal", user, %{})
    { :ok, _ } = Package.create("ex_doc", user, %{})
    { :ok, _ } = Install.create("0.0.1", "0.13.0-dev")
    { :ok, _ } = Install.create("0.1.0", "0.13.1-dev")
    :ok
  end

  teardown do
    :ok = RegistryBuilder.stop
  end

  defp build do
    RegistryBuilder.sync_rebuild
  end

  defp open_table do
    { :ok, tid } = :ets.file2tab('tmp/registry.ets')
    tid
  end

  defp close_table(tid) do
    :ets.delete(tid)
  end

  test "registry is versioned" do
    build()
    tid = open_table()

    try do
      assert [{ :"$$version$$", 2 }] = :ets.lookup(tid, :"$$version$$")
    after
      close_table(tid)
    end
  end

  test "registry includes installs" do
    build()
    tid = open_table()

    try do
      assert [{ :"$$installs$$", installs }] = :ets.lookup(tid, :"$$installs$$")
      assert [{"0.0.1", "0.13.0-dev"}, {"0.1.0", "0.13.1-dev"}] = installs
    after
      close_table(tid)
    end
  end

  test "registry is in correct format" do
    postgrex = Package.get("postgrex")
    decimal = Package.get("decimal")

    Release.create(decimal, "0.0.1", [], "")
    Release.create(decimal, "0.0.2", [{ "ex_doc", "0.0.0" }], "")
    Release.create(postgrex, "0.0.2", [{ "decimal", "~> 0.0.1" }, { "ex_doc", "0.1.0" }], "")

    build()
    tid = open_table()

    try do
      assert length(:ets.match_object(tid, :_)) == 7

      assert [ { "decimal", [["0.0.1", "0.0.2"]] } ] = :ets.lookup(tid, "decimal")

      assert [ { { "decimal", "0.0.1" }, [[]] } ] =
             :ets.lookup(tid, { "decimal", "0.0.1" })

      assert [{ "postgrex", [["0.0.2"]] }] =
             :ets.lookup(tid, "postgrex")

      reqs = :ets.lookup(tid, { "postgrex", "0.0.2" }) |> List.first |> elem(1) |> List.first
      assert length(reqs) == 2
      assert Enum.find(reqs, &(&1 == ["decimal", "~> 0.0.1", false]))
      assert Enum.find(reqs, &(&1 == ["ex_doc", "0.1.0", false]))

      assert [] = :ets.lookup(tid, "ex_doc")
    after
      close_table(tid)
    end
  end

  test "building is blocking" do
    postgrex = Package.get("postgrex")
    decimal = Package.get("decimal")

    Release.create(decimal, "0.0.1", [], "")
    Release.create(decimal, "0.0.2", [{ "ex_doc", "0.0.0" }], "")
    Release.create(postgrex, "0.0.2", [{ "decimal", "~> 0.0.1" }, { "ex_doc", "0.1.0" }], "")

    RegistryBuilder.async_rebuild
    RegistryBuilder.async_rebuild
    RegistryBuilder.sync_rebuild

    tid = open_table()
    close_table(tid)
  end
end
