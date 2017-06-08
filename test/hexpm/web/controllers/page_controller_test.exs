defmodule Hexpm.Web.PageControllerTest do
  use Hexpm.ConnCase

  setup do
    first_date  = ~N[2014-05-01 10:11:12]
    second_date = ~N[2014-05-02 10:11:12]
    third_date   = ~N[2014-05-03 10:11:12]

    p1 = insert(:package, inserted_at: first_date, updated_at: first_date)
    p2 = insert(:package, inserted_at: second_date, updated_at: second_date)
    p3 = insert(:package, inserted_at: third_date, updated_at: third_date)

    insert(:release, package: p1, version: "0.0.1", inserted_at: ~N[2014-05-03 10:11:01])
    insert(:release, package: p1, version: "0.0.2", inserted_at: ~N[2014-05-03 10:11:02])
    insert(:release, package: p1, version: "0.1.0", inserted_at: ~N[2014-05-03 10:11:03])
    insert(:release, package: p2, version: "0.0.1", inserted_at: ~N[2014-05-03 10:11:04])
    insert(:release, package: p2, version: "0.0.2", inserted_at: ~N[2014-05-03 10:11:05])
    insert(:release, package: p3, version: "0.0.1", inserted_at: ~N[2014-05-03 10:11:06])

    %{package1: p1, package2: p2, package3: p3}
  end

  test "index", %{package1: package1, package2: package2} do
    logfile1 = read_log("s3_logs_1.txt", package1, package2)
    logfile2 = read_log("s3_logs_2.txt", package1, package2)

    Hexpm.Store.put("region", "bucket", "hex/2013-12-01-21-32-16-E568B2907131C0C0", logfile1, [])
    Hexpm.Store.put("region", "bucket", "hex/2013-12-01-21-32-19-E568B2907131C0C0", logfile2, [])
    Mix.Tasks.Hexpm.Stats.run(~D[2013-12-01], [["bucket", "region"]])

    conn = get build_conn(), "/"

    package1_name = package1.name
    package2_name = package2.name

    assert conn.status == 200
    assert conn.assigns.total["all"] == 9
    assert conn.assigns.total["week"] == 0
    assert conn.assigns.num_packages == 3
    assert conn.assigns.num_releases == 6
    assert Enum.count(conn.assigns.releases_new) == 6
    assert Enum.count(conn.assigns.package_new) == 3
    assert [{^package1_name, %NaiveDateTime{}, %Hexpm.Repository.PackageMetadata{}, 7},
            {^package2_name, %NaiveDateTime{}, %Hexpm.Repository.PackageMetadata{}, 2}] = conn.assigns.package_top
  end

  defp read_log(path, package1, package2) do
    read_fixture(path)
    |> String.replace("{package1}", package1.name)
    |> String.replace("{package2}", package2.name)
  end
end
