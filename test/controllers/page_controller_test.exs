defmodule HexWeb.PageControllerTest do
  use HexWeb.ConnCase, async: true

  alias HexWeb.Package
  alias HexWeb.Release

  defp release_create(package, version, app, requirements, checksum, inserted_at) do
    release = Release.build(package, rel_meta(%{version: version, app: app, requirements: requirements}), checksum)
              |> HexWeb.Repo.insert!
    Ecto.Changeset.change(release, inserted_at: inserted_at)
    |> HexWeb.Repo.update!
  end

  setup do
    first_date  = ~N[2014-05-01 10:11:12]
    second_date = ~N[2014-05-02 10:11:12]
    last_date   = ~N[2014-05-03 10:11:12]

    eric = create_user("eric", "eric@example.com", "ericeric")

    foo = Package.build(eric, %{name: "foo", inserted_at: first_date, updated_at: first_date, meta: %{description: "foo", licenses: ["Apache"]}}) |> HexWeb.Repo.insert!
    bar = Package.build(eric, %{name: "bar", inserted_at: second_date, updated_at: second_date, meta: %{description: "bar", licenses: ["Apache"]}}) |> HexWeb.Repo.insert!
    other = Package.build(eric, %{name: "other", inserted_at: last_date, updated_at: last_date, meta: %{description: "other", licenses: ["Apache"]}}) |> HexWeb.Repo.insert!

    release_create(foo, "0.0.1", "foo", [], "", ~N[2014-05-03 10:11:01])
    release_create(foo, "0.0.2", "foo", [], "", ~N[2014-05-03 10:11:02])
    release_create(foo, "0.1.0", "foo", [], "", ~N[2014-05-03 10:11:03])
    release_create(bar, "0.0.1", "bar", [], "", ~N[2014-05-03 10:11:04])
    release_create(bar, "0.0.2", "bar", [], "", ~N[2014-05-03 10:11:05])
    release_create(other, "0.0.1", "other", [], "", ~N[2014-05-03 10:11:06])
    :ok
  end

  test "index" do
    path     = Path.join([__DIR__, "..", "fixtures"])
    logfile1 = File.read!(Path.join(path, "s3_logs_1.txt"))
    logfile2 = File.read!(Path.join(path, "s3_logs_2.txt"))

    HexWeb.Store.put("region", "bucket", "hex/2013-12-01-21-32-16-E568B2907131C0C0", logfile1, [])
    HexWeb.Store.put("region", "bucket", "hex/2013-12-01-21-32-19-E568B2907131C0C0", logfile2, [])
    HexWeb.StatsJob.run(~D[2013-12-01], [["bucket", "region"]])

    conn = get build_conn(), "/"

    assert conn.status == 200
    assert conn.assigns.total["all"] == 9
    assert conn.assigns.total["week"] == 0
    assert [{"foo", %NaiveDateTime{}, %HexWeb.PackageMetadata{}, 7}, {"bar", %NaiveDateTime{}, %HexWeb.PackageMetadata{}, 2}] = conn.assigns.package_top
    assert conn.assigns.num_packages == 3
    assert conn.assigns.num_releases == 6
    assert Enum.count(conn.assigns.releases_new) == 6
    assert Enum.count(conn.assigns.package_new) == 3
  end
end
