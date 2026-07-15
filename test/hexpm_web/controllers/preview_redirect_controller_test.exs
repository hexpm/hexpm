defmodule HexpmWeb.PreviewRedirectControllerTest do
  use HexpmWeb.ConnCase, async: true

  test "redirects the Preview host root to packages" do
    conn = request("/")
    assert redirected_to(conn, 301) == "http://localhost:5000/packages"
  end

  test "redirects the Preview sitemap to its Hexpm path" do
    conn = request("/sitemap.xml")
    assert redirected_to(conn, 301) == "http://localhost:5000/preview/sitemap.xml"
  end

  test "redirects Preview host file paths directly to package files" do
    conn = request("/preview/package/1.0.0/show/lib/file.ex?line=1")

    assert redirected_to(conn, 301) ==
             "http://localhost:5000/packages/package/1.0.0/files/lib/file.ex?line=1"
  end

  test "redirects Preview host filename query links directly to package files" do
    conn = request("/preview/package/1.0.0?filename=include%2Fheader.hrl")

    assert redirected_to(conn, 301) ==
             "http://localhost:5000/packages/package/1.0.0/files/include/header.hrl"
  end

  test "redirects legacy Hexpm Preview file paths" do
    conn = get(build_conn(), "/preview/package/1.0.0/show/lib/file.ex")

    assert redirected_to(conn, 301) ==
             "http://localhost:5000/packages/package/1.0.0/files/lib/file.ex"
  end

  test "resolves legacy latest Preview paths to a pinned version" do
    Hexpm.Store.put(:preview_bucket, "latest_versions/package", "2.0.0")
    conn = get(build_conn(), "/preview/package/show/README.md")

    assert redirected_to(conn, 301) ==
             "http://localhost:5000/packages/package/2.0.0/files/README.md"
  end

  test "normalizes historical versioned package sitemap paths" do
    conn = request("/preview/package/1.0.0/sitemap.xml")
    assert redirected_to(conn, 301) == "http://localhost:5000/preview/package/sitemap.xml"
  end

  test "redirects Preview package sitemaps to their Hexpm paths" do
    conn = request("/preview/package/sitemap.xml")
    assert redirected_to(conn, 301) == "http://localhost:5000/preview/package/sitemap.xml"
  end

  defp request(path) do
    build_conn()
    |> Map.put(:host, "preview.localhost")
    |> get(path)
  end
end
