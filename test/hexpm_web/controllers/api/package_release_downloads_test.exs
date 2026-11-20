defmodule HexpmWeb.API.PackageReleaseDownloadsTest do
  use HexpmWeb.ConnCase, async: false

  setup do
    package = insert(:package)
    release = insert(:release, package: package, version: "0.0.1")
    insert(:release, package: package, version: "1.0.0")

    %{package: package, release: release}
  end

  defp release_downloads(package, query \\ "?release_downloads=true") do
    result =
      build_conn()
      |> get("/api/packages/#{package.name}#{query}")
      |> json_response(200)

    Map.new(result["releases"], &{&1["version"], &1["downloads"]})
  end

  describe "GET /api/packages/:name" do
    test "includes the downloads of each release when the flag is enabled", %{
      package: package,
      release: release
    } do
      insert(:download,
        package: package,
        release: release,
        downloads: 1,
        day: database_days_ago(1)
      )

      insert(:download,
        package: package,
        release: release,
        downloads: 10,
        day: database_days_ago(12)
      )

      insert(:download,
        package: package,
        release: release,
        downloads: 100,
        day: database_days_ago(91)
      )

      :ok = Hexpm.Repo.refresh_view(Hexpm.Repository.ReleaseDownloadBreakdown)

      put_feature_flag(:release_download_breakdowns, mode: :enabled)

      downloads = release_downloads(package)

      assert downloads["0.0.1"] == %{"day" => 1, "week" => 1, "recent" => 11, "all" => 111}
      assert downloads["1.0.0"] == %{}
    end

    test "leaves them out without the parameter", %{package: package} do
      put_feature_flag(:release_download_breakdowns, mode: :enabled)

      for query <- ["", "?release_downloads=false", "?release_downloads=1"] do
        assert release_downloads(package, query) == %{"0.0.1" => nil, "1.0.0" => nil}
      end
    end

    test "ignores the parameter when the flag is off", %{package: package} do
      put_feature_flag(:release_download_breakdowns, mode: :off)

      assert release_downloads(package) == %{"0.0.1" => nil, "1.0.0" => nil}
    end
  end
end
