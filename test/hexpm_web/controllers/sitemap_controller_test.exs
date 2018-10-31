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
    sitemap = read_fixture("packages_sitemap.xml") |> String.replace("{package}", package.name)
    assert response(conn, 200) == sitemap
  end

  test "GET /docs_sitemap.xml", %{package: package} do
    conn = get(build_conn(), "/docs_sitemap.xml")
    sitemap = read_fixture("docs_sitemap.xml") |> String.replace("{package}", package.name)
    assert response(conn, 200) == sitemap
  end
end
