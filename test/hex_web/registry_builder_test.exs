defmodule HexWeb.RegistryBuilderTest do
  use HexWebTest.Case

  alias HexWeb.User
  alias HexWeb.Package
  alias HexWeb.Release
  alias HexWeb.RegistryBuilder

  @dets_table :hex_registry_test

  setup do
    { :ok, _ } = RegistryBuilder.start_link
    { :ok, user } = User.create("eric", "eric", "eric")
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
    dets_opts = [
      file: RegistryBuilder.latest_file,
      ram_file: true,
      access: :read,
      type: :duplicate_bag ]
    { :ok, @dets_table } = :dets.open_file(@dets_table, dets_opts)
  end

  defp close_table do
    :ok = :dets.close(@dets_table)
  end

  test "registry is versioned" do
    build()
    open_table()
    assert [{ :"$$version$$", 1 }] = :dets.lookup(@dets_table, :"$$version$$")
  after
    close_table()
  end

  test "registry is in correct format" do
    postgrex = Package.get("postgrex")
    decimal = Package.get("decimal")

    Release.create(decimal, "0.0.1", "dec_url1", "dec_ref1", [])
    Release.create(decimal, "0.0.2", "dec_url2", "dec_ref2", [{ "ex_doc", "0.0.0" }])
    Release.create(postgrex, "0.0.2", "pg_url1", "pg_ref1", [{ "decimal", "~> 0.0.1" }, { "ex_doc", "0.1.0" }])

    build()
    open_table()

    assert length(:dets.match_object(@dets_table, :_)) == 4

    assert [ { "decimal", "0.0.1", [], "dec_url1", "dec_ref1" },
             { "decimal", "0.0.2", [{ "ex_doc", "0.0.0" }], "dec_url2", "dec_ref2" } ] =
           :dets.lookup(@dets_table, "decimal")

    assert [{ "postgrex", "0.0.2", _, "pg_url1", "pg_ref1" }] =
           :dets.lookup(@dets_table, "postgrex")

    reqs = :dets.lookup(@dets_table, "postgrex") |> List.first |> elem(2)
    assert length(reqs) == 2
    assert Enum.find(reqs, &(&1 == { "decimal", "~> 0.0.1" }))
    assert Enum.find(reqs, &(&1 == { "ex_doc", "0.1.0" }))

    assert [] = :dets.lookup(@dets_table, "ex_doc")
  after
    close_table()
  end

  test "rebuilding does not break current open files" do
    build()
    open_table()

    decimal = Package.get("decimal")
    Release.create(decimal, "0.0.1", "dec_url1", "dec_ref1", [])
    build()

    assert length(:dets.match_object(@dets_table, :_)) == 1
  after
    close_table()
  end

  test "fetch registry from if stale" do
    build()
    open_table()
    assert length(:dets.match_object(@dets_table, :_)) == 1
    close_table()

    decimal = Package.get("decimal")
    Release.create(decimal, "0.0.1", "dec_url1", "dec_ref1", [])

    { temp_file, version } = HexWeb.RegistryBuilder.build_dets()
    HexWeb.Registry.create(version, File.read!(temp_file))

    open_table()

    assert length(:dets.match_object(@dets_table, :_)) == 2
  after
    close_table()
  end
end
