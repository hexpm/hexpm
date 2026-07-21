defmodule HexpmWeb.SitemapControllerTest do
  use HexpmWeb.ConnCase, async: true

  setup do
    time = ~N[2014-04-17 14:00:00.000]
    package = insert(:package, name: "xyz", updated_at: time, docs_updated_at: time)
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

  test "GET /docs_sitemap.xml keeps one entry when a package has multiple docs releases", %{
    package: package
  } do
    insert(:release, package: package, version: "0.2.0", has_docs: true)

    conn = get(build_conn(), "/docs_sitemap.xml")

    expected =
      "docs_sitemap.xml"
      |> read_fixture()
      |> String.replace("{package}", package.name)

    assert response(conn, 200) == expected
  end

  test "GET /preview/sitemap.xml", %{package: package} do
    conn =
      build_conn()
      |> put_req_header("accept", "application/xml")
      |> get("/preview/sitemap.xml")

    assert response(conn, 200) =~ "/preview/#{package.name}/sitemap.xml"
    assert get_resp_header(conn, "cache-control") == ["public, max-age=300"]
  end

  test "GET /preview/:package/sitemap.xml renders latest files", %{package: package} do
    Hexpm.Store.put(:preview_bucket, "latest_versions/#{package.name}", "0.1.0")

    Hexpm.Store.put(
      :preview_bucket,
      "file_lists/#{package.name}-0.1.0.json",
      JSON.encode!(["README.md", "docs/a & #<.html"])
    )

    conn =
      build_conn()
      |> put_req_header("accept", "application/xml")
      |> get("/preview/#{package.name}/sitemap.xml")

    body = response(conn, 200)

    assert body =~ "/packages/#{package.name}/0.1.0/files/README.md"
    assert body =~ "docs/a%20%26%20%23%3C.html"
    refute body =~ "docs/a & #<.html"
    assert get_resp_header(conn, "cache-control") == ["public, max-age=300"]
  end

  test "GET /preview/:package/sitemap.xml returns 404 without Preview files", %{package: package} do
    conn = get(build_conn(), "/preview/#{package.name}/sitemap.xml")
    assert response(conn, 404) == "Not Found"
  end
end
