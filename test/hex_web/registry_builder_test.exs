defmodule HexWeb.RegistryBuilderTest do
  use HexWebTest.Case

  alias HexWeb.User
  alias HexWeb.Package
  alias HexWeb.Release
  alias HexWeb.RegistryBuilder

  @ets_table :hex_registry

  setup do
    { :ok, _ } = RegistryBuilder.start_link
    { :ok, user } = User.create("eric", "eric@mail.com", "eric")
    { :ok, _ } = Package.create("postgrex", user, [])
    { :ok, _ } = Package.create("decimal", user, [])
    { :ok, _ } = Package.create("ex_doc", user, [])
    :ok
  end

  teardown do
    :ok = RegistryBuilder.stop
  end

  defp build do
    RegistryBuilder.rebuild
    RegistryBuilder.wait_for_build
  end

  defp open_table do
    file = String.to_char_list!(RegistryBuilder.latest_file)
    { :ok, tid } = :ets.file2tab(file)
    tid
  end

  defp close_table(tid) do
    :ets.delete(tid)
  end

  test "registry is versioned" do
    build()
    tid = open_table()

    try do
      assert [{ :"$$version$$", 1 }] = :ets.lookup(tid, :"$$version$$")
    after
      close_table(tid)
    end
  end

  test "registry is in correct format" do
    postgrex = Package.get("postgrex")
    decimal = Package.get("decimal")

    Release.create(decimal, "0.0.1", "dec_url1", "dec_ref1", [])
    Release.create(decimal, "0.0.2", "dec_url2", "dec_ref2", [{ "ex_doc", "0.0.0" }])
    Release.create(postgrex, "0.0.2", "pg_url1", "pg_ref1", [{ "decimal", "~> 0.0.1" }, { "ex_doc", "0.1.0" }])

    build()
    tid = open_table()

    try do
      assert length(:ets.match_object(tid, :_)) == 6

      assert [ { "decimal", ["0.0.1", "0.0.2"] } ] = :ets.lookup(tid, "decimal")

      assert [ { { "decimal", "0.0.1" }, [], "dec_url1", "dec_ref1" } ] =
             :ets.lookup(tid, { "decimal", "0.0.1" })

      assert [{ "postgrex", ["0.0.2"] }] =
             :ets.lookup(tid, "postgrex")

      reqs = :ets.lookup(tid, { "postgrex", "0.0.2" }) |> List.first |> elem(1)
      assert length(reqs) == 2
      assert Enum.find(reqs, &(&1 == { "decimal", "~> 0.0.1" }))
      assert Enum.find(reqs, &(&1 == { "ex_doc", "0.1.0" }))

      assert [] = :ets.lookup(tid, "ex_doc")
    after
      close_table(tid)
    end
  end

  test "rebuilding does not break current open files" do
    build()
    tid = open_table()

    try do
      decimal = Package.get("decimal")
      Release.create(decimal, "0.0.1", "dec_url1", "dec_ref1", [])
      build()

      assert length(:ets.match_object(tid, :_)) == 1
    after
      close_table(tid)
    end
  end

  test "fetch registry from if stale" do
    build()

    decimal = Package.get("decimal")
    Release.create(decimal, "0.0.1", "dec_url1", "dec_ref1", [])

    { temp_file, version } = HexWeb.RegistryBuilder.build_ets()
    HexWeb.Registry.create(version, File.read!(temp_file))

    tid = open_table()

    try do
      assert length(:ets.match_object(tid, :_)) == 3
    after
      close_table(tid)
    end
  end
end
