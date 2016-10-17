defmodule Mix.Tasks.Hexweb.StatsTest do
  use HexWeb.ModelCase, async: true

  alias HexWeb.Package
  alias HexWeb.Release

  setup do
    user = create_user("eric", "eric@mail.com", "ericeric")

    foo   = Package.build(user, pkg_meta(%{name: "foo", description: "Foo"})) |> HexWeb.Repo.insert!
    bar   = Package.build(user, pkg_meta(%{name: "bar", description: "Bar"})) |> HexWeb.Repo.insert!
    other = Package.build(user, pkg_meta(%{name: "other", description: "Other"})) |> HexWeb.Repo.insert!

    Release.build(foo, rel_meta(%{version: "0.0.1", app: "foo"}), "") |> HexWeb.Repo.insert!
    Release.build(foo, rel_meta(%{version: "0.0.2", app: "foo"}), "") |> HexWeb.Repo.insert!
    Release.build(foo, rel_meta(%{version: "0.1.0", app: "foo"}), "") |> HexWeb.Repo.insert!
    Release.build(bar, rel_meta(%{version: "0.0.1", app: "bar"}), "") |> HexWeb.Repo.insert!
    Release.build(bar, rel_meta(%{version: "0.0.2", app: "bar"}), "") |> HexWeb.Repo.insert!
    Release.build(bar, rel_meta(%{version: "0.0.3-rc.1", app: "bar"}), "") |> HexWeb.Repo.insert!
    Release.build(other, rel_meta(%{version: "0.0.1", app: "other"}), "") |> HexWeb.Repo.insert!

    %{foo: foo, bar: bar, other: other}
  end

  test "counts all downloads", %{foo: foo, bar: bar} do
    {bucket, region} =
      if buckets = Application.get_env(:hex_web, :logs_buckets) do
        [[bucket, region]] = buckets
        {bucket, region}
      else
        {nil, nil}
      end

    buckets = [[bucket, region]]

    path     = Path.join([__DIR__, "..", "..", "..", "fixtures"])
    logfile1 = File.read!(Path.join(path, "s3_logs_1.txt"))
    logfile2 = File.read!(Path.join(path, "s3_logs_2.txt"))
    logfile3 = File.read!(Path.join(path, "fastly_logs_1.txt")) |> :zlib.gzip
    logfile4 = File.read!(Path.join(path, "fastly_logs_2.txt")) |> :zlib.gzip

    HexWeb.Store.put(region, bucket, "hex/2013-11-01-21-32-16-E568B2907131C0C0", logfile1, [])
    HexWeb.Store.put(region, bucket, "hex/2013-11-02-21-32-17-E568B2907131C0C0", logfile1, [])
    HexWeb.Store.put(region, bucket, "hex/2013-11-03-21-32-18-E568B2907131C0C0", logfile1, [])
    HexWeb.Store.put(region, bucket, "hex/2013-11-01-21-32-19-E568B2907131C0C0", logfile2, [])
    HexWeb.Store.put(region, bucket, "fastly_hex/2013-11-01T14:00:00.000-tzletcEGGiI7atIAAAAA.log.gz", logfile3, [])
    HexWeb.Store.put(region, bucket, "fastly_hex/2013-11-01T15:00:00.000-tzletcEGGiI7atIAAAAA.log.gz", logfile4, [])

    HexWeb.StatsJob.run(~D[2013-11-01], buckets)

    rel1 = HexWeb.Repo.get_by!(assoc(foo, :releases), version: "0.0.1")
    rel2 = HexWeb.Repo.get_by!(assoc(foo, :releases), version: "0.0.2")
    rel3 = HexWeb.Repo.get_by!(assoc(bar, :releases), version: "0.0.2")
    rel4 = HexWeb.Repo.get_by!(assoc(bar, :releases), version: "0.0.3-rc.1")

    downloads = HexWeb.Repo.all(HexWeb.Download)
    assert length(downloads) == 4

    assert Enum.find(downloads, &(&1.release_id == rel1.id)).downloads == 11
    assert Enum.find(downloads, &(&1.release_id == rel2.id)).downloads == 3
    assert Enum.find(downloads, &(&1.release_id == rel3.id)).downloads == 3
    assert Enum.find(downloads, &(&1.release_id == rel4.id)).downloads == 1
  end
end
