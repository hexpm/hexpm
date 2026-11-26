defmodule Hexpm.Repository.ReleaseDownloadBreakdownTest do
  use Hexpm.DataCase

  alias Hexpm.Repository.{ReleaseDownload, ReleaseDownloadBreakdown}

  test "release_download_breakdowns with view all matches release_downloads" do
    package = insert(:package)
    release1 = insert(:release, package: package, version: "0.0.1")
    release2 = insert(:release, package: package, version: "0.0.2")

    insert(:download,
      package: package,
      release: release1,
      downloads: 100,
      day: database_days_ago(91)
    )

    insert(:download,
      package: package,
      release: release1,
      downloads: 10,
      day: database_days_ago(5)
    )

    insert(:download,
      package: package,
      release: release2,
      downloads: 5,
      day: database_days_ago(3)
    )

    :ok = Hexpm.Repo.refresh_view(ReleaseDownload, concurrently: false)
    :ok = Hexpm.Repo.refresh_view(ReleaseDownloadBreakdown, concurrently: false)

    release_downloads =
      Hexpm.Repo.all(ReleaseDownload) |> Enum.map(fn rd -> {rd.release_id, rd.downloads} end)

    all_release_download_breakdown =
      Hexpm.Repo.all(ReleaseDownloadBreakdown)
      |> Enum.filter(fn breakdown -> breakdown.view == "all" end)
      |> Enum.map(fn breakdown -> {breakdown.release_id, breakdown.downloads} end)

    assert Enum.sort(release_downloads) == Enum.sort(all_release_download_breakdown)
  end
end
