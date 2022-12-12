defmodule HexpmWeb.PageControllerTest do
  use HexpmWeb.ConnCase

  alias Hexpm.Repository.{
    PackageDownload,
    ReleaseDownload
  }

  setup do
    seconds_in_a_day = 86400

    today = NaiveDateTime.utc_now()

    first_date = NaiveDateTime.add(today, -14 * seconds_in_a_day)
    second_date = NaiveDateTime.add(today, -13 * seconds_in_a_day)
    third_date = NaiveDateTime.add(today, -12 * seconds_in_a_day)

    p1 = insert(:package, inserted_at: first_date, updated_at: first_date)
    p2 = insert(:package, inserted_at: second_date, updated_at: second_date)
    p3 = insert(:package, inserted_at: third_date, updated_at: third_date)

    base_date = NaiveDateTime.add(today, -12 * seconds_in_a_day)
    rel1 = insert(:release, package: p1, version: "0.0.1", inserted_at: %{base_date | second: 01})
    insert(:release, package: p1, version: "0.0.2", inserted_at: %{base_date | second: 02})
    insert(:release, package: p1, version: "0.1.0", inserted_at: %{base_date | second: 03})
    rel2 = insert(:release, package: p2, version: "0.0.1", inserted_at: %{base_date | second: 04})
    insert(:release, package: p2, version: "0.0.2", inserted_at: %{base_date | second: 05})
    insert(:release, package: p3, version: "0.0.1", inserted_at: %{base_date | second: 06})

    insert(:download,
      package: p1,
      release: rel1,
      downloads: 7,
      day: NaiveDateTime.to_date(base_date)
    )

    insert(:download,
      package: p2,
      release: rel2,
      downloads: 2,
      day: NaiveDateTime.to_date(base_date)
    )

    old_date = today |> NaiveDateTime.add(-91 * seconds_in_a_day) |> NaiveDateTime.to_date()
    insert(:download, package: p2, release: rel2, downloads: 1, day: old_date)

    Repo.refresh_view(PackageDownload)
    Repo.refresh_view(ReleaseDownload)

    %{package1: p1, package2: p2, package3: p3}
  end

  test "index", c do
    conn = get(build_conn(), "/")

    assert conn.status == 200
    assert conn.assigns.total["all"] == 10
    assert conn.assigns.total["week"] == 0
    assert conn.assigns.num_packages == 3
    assert conn.assigns.num_releases == 6
    assert Enum.count(conn.assigns.releases_new) == 6
    assert Enum.count(conn.assigns.package_new) == 3

    assert [{package1, 7}, {package2, 2}] = conn.assigns.package_top
    assert package1.id == c.package1.id
    assert package1.latest_release.version == "0.1.0"
    assert package2.id == c.package2.id
    assert package2.latest_release.version == "0.0.2"
  end
end
