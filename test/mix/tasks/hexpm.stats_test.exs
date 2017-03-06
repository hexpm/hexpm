defmodule Mix.Tasks.Hexweb.StatsTest do
  use Hexpm.DataCase, async: true

  alias Hexpm.Repository.Download
  alias Hexpm.Repository.Package
  alias Hexpm.Repository.Release
  alias Hexpm.Store

  setup do
    user = create_user("eric", "eric@mail.com", "ericeric")

    foo   = Package.build(user, pkg_meta(%{name: "foo", description: "Foo"})) |> Repo.insert!
    bar   = Package.build(user, pkg_meta(%{name: "bar", description: "Bar"})) |> Repo.insert!
    other = Package.build(user, pkg_meta(%{name: "other", description: "Other"})) |> Repo.insert!

    Release.build(foo, rel_meta(%{version: "0.0.1", app: "foo"}), "") |> Repo.insert!
    Release.build(foo, rel_meta(%{version: "0.0.2", app: "foo"}), "") |> Repo.insert!
    Release.build(foo, rel_meta(%{version: "0.1.0", app: "foo"}), "") |> Repo.insert!
    Release.build(bar, rel_meta(%{version: "0.0.1", app: "bar"}), "") |> Repo.insert!
    Release.build(bar, rel_meta(%{version: "0.0.2", app: "bar"}), "") |> Repo.insert!
    Release.build(bar, rel_meta(%{version: "0.0.3-rc.1", app: "bar"}), "") |> Repo.insert!
    Release.build(other, rel_meta(%{version: "0.0.1", app: "other"}), "") |> Repo.insert!

    %{foo: foo, bar: bar, other: other}
  end

  test "counts all downloads", %{foo: foo, bar: bar} do
    {bucket, region} =
      if buckets = Application.get_env(:hexpm, :logs_buckets) do
        [[bucket, region]] = buckets
        {bucket, region}
      else
        {nil, nil}
      end

    buckets = [[bucket, region]]

    logfile1 = read_fixture("s3_logs_1.txt")
    logfile2 = read_fixture("s3_logs_2.txt")
    logfile3 = read_fixture("fastly_logs_1.txt") |> :zlib.gzip
    logfile4 = read_fixture("fastly_logs_2.txt") |> :zlib.gzip

    Store.put(region, bucket, "hex/2013-11-01-21-32-16-E568B2907131C0C0", logfile1, [])
    Store.put(region, bucket, "hex/2013-11-02-21-32-17-E568B2907131C0C0", logfile1, [])
    Store.put(region, bucket, "hex/2013-11-03-21-32-18-E568B2907131C0C0", logfile1, [])
    Store.put(region, bucket, "hex/2013-11-01-21-32-19-E568B2907131C0C0", logfile2, [])
    Store.put(region, bucket, "fastly_hex/2013-11-01T14:00:00.000-tzletcEGGiI7atIAAAAA.log.gz", logfile3, [])
    Store.put(region, bucket, "fastly_hex/2013-11-01T15:00:00.000-tzletcEGGiI7atIAAAAA.log.gz", logfile4, [])

    Mix.Tasks.Hexweb.Stats.run(~D[2013-11-01], buckets)

    rel1 = Repo.get_by!(assoc(foo, :releases), version: "0.0.1")
    rel2 = Repo.get_by!(assoc(foo, :releases), version: "0.0.2")
    rel3 = Repo.get_by!(assoc(bar, :releases), version: "0.0.2")
    rel4 = Repo.get_by!(assoc(bar, :releases), version: "0.0.3-rc.1")

    downloads = Hexpm.Repo.all(Download)
    assert length(downloads) == 4

    assert Enum.find(downloads, &(&1.release_id == rel1.id)).downloads == 11
    assert Enum.find(downloads, &(&1.release_id == rel2.id)).downloads == 3
    assert Enum.find(downloads, &(&1.release_id == rel3.id)).downloads == 3
    assert Enum.find(downloads, &(&1.release_id == rel4.id)).downloads == 1
  end
end
