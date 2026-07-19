defmodule HexpmWeb.PackageLayoutAssignsTest do
  use HexpmWeb.ConnCase, async: true

  alias HexpmWeb.PackageLayoutAssigns

  test "skips sidebar and dependant data for anonymous wide layouts" do
    package = insert(:package) |> Repo.preload(:repository)
    release = insert(:release, package: package)

    assigns =
      PackageLayoutAssigns.for_package(nil, package,
        releases: [release],
        current_release: release,
        sidebar?: false,
        dependants_count?: false
      )

    assert assigns[:owners] == []
    assert assigns[:downloads] == %{}
    assert assigns[:daily_graph] == []
    assert assigns[:dependants_count] == nil
  end
end
