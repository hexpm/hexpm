defmodule Mix.Tasks.Hexpm.StatsTest do
  use Hexpm.DataCase  

  alias Hexpm.Repository.Download
  alias Hexpm.Store

  setup do
    [package1, package2, package3] = insert_list(3, :package)
    insert(:release, package: package1, version: "0.0.1")
    insert(:release, package: package1, version: "0.0.2")
    insert(:release, package: package1, version: "0.1.0")
    insert(:release, package: package2, version: "0.0.1")
    insert(:release, package: package2, version: "0.0.2")
    insert(:release, package: package2, version: "0.0.3-rc.1")
    insert(:release, package: package3, version: "0.0.1")

    %{package1: package1, package2: package2, package3: package3}
  end

  test "counts all downloads", %{package1: package1, package2: package2} do
    {bucket, region} =
      if buckets = Application.get_env(:hexpm, :logs_buckets) do
        [[bucket, region]] = buckets
        {bucket, region}
      else
        {nil, nil}
      end

    buckets = [[bucket, region]]

    logfile1 = read_log("s3_logs_1.txt", package1, package2)
    logfile2 = read_log("s3_logs_2.txt", package1, package2)
    logfile3 = read_log("fastly_logs_1.txt", package1, package2) |> :zlib.gzip
    logfile4 = read_log("fastly_logs_2.txt", package1, package2) |> :zlib.gzip

    Store.put(region, bucket, "hex/2013-11-01-21-32-16-E568B2907131C0C0", logfile1, [])
    Store.put(region, bucket, "hex/2013-11-02-21-32-17-E568B2907131C0C0", logfile1, [])
    Store.put(region, bucket, "hex/2013-11-03-21-32-18-E568B2907131C0C0", logfile1, [])
    Store.put(region, bucket, "hex/2013-11-01-21-32-19-E568B2907131C0C0", logfile2, [])
    Store.put(region, bucket, "fastly_hex/2013-11-01T14:00:00.000-tzletcEGGiI7atIAAAAA.log.gz", logfile3, [])
    Store.put(region, bucket, "fastly_hex/2013-11-01T15:00:00.000-tzletcEGGiI7atIAAAAA.log.gz", logfile4, [])

    Mix.Tasks.Hexpm.Stats.run(~D[2013-11-01], buckets)

    rel1 = Repo.get_by!(assoc(package1, :releases), version: "0.0.1")
    rel2 = Repo.get_by!(assoc(package1, :releases), version: "0.0.2")
    rel3 = Repo.get_by!(assoc(package2, :releases), version: "0.0.2")
    rel4 = Repo.get_by!(assoc(package2, :releases), version: "0.0.3-rc.1")

    downloads = Hexpm.Repo.all(Download)
    assert length(downloads) == 4

    assert Enum.find(downloads, &(&1.release_id == rel1.id)).downloads == 11
    assert Enum.find(downloads, &(&1.release_id == rel2.id)).downloads == 3
    assert Enum.find(downloads, &(&1.release_id == rel3.id)).downloads == 3
    assert Enum.find(downloads, &(&1.release_id == rel4.id)).downloads == 1
  end

  defp read_log(path, package1, package2) do
    read_fixture(path)
    |> String.replace("{package1}", package1.name)
    |> String.replace("{package2}", package2.name)
  end
end
