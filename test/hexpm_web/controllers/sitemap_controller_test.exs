defmodule HexpmWeb.SitemapControllerTest do
  use HexpmWeb.ConnCase, async: true

  setup do
    time = ~N[2014-04-17 14:00:00.000]
    package = insert(:package, updated_at: time, docs_updated_at: time)
    insert(:release, package: package, version: "0.1.0", has_docs: true)

    %{package: package}
  end

  test "GET /sitemap.xml", %{package: package} do
    conn = get(build_conn(), "/sitemap.xml")

    expected =
      "packages_sitemap.xml"
      |> read_fixture()
      |> String.replace("{package}", package.name)

    assert response(conn, 200) == expected
  end

  test "GET /docs_sitemap.xml", %{package: package} do
    conn = get(build_conn(), "/docs_sitemap.xml")

    expected =
      "docs_sitemap.xml"
      |> read_fixture()
      |> String.replace("{package}", package.name)

    assert response(conn, 200) == expected
  end

  test "GET /preview_sitemap.xml", %{package: package} do
    conn = get(build_conn(), "/preview_sitemap.xml")
    assert response(conn, 200) =~ "/preview/#{package.name}/0.1.0/sitemap.xml"
  end
end
