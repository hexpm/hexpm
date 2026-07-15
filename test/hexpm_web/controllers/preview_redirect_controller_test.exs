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

  test "preserves Preview paths and query strings" do
    conn = request("/preview/package/1.0.0/show/lib/file.ex?line=1")

    assert redirected_to(conn, 301) ==
             "http://localhost:5000/preview/package/1.0.0/show/lib/file.ex?line=1"
  end

  test "normalizes historical versioned package sitemap paths" do
    conn = request("/preview/package/1.0.0/sitemap.xml")
    assert redirected_to(conn, 301) == "http://localhost:5000/preview/package/sitemap.xml"
  end

  defp request(path) do
    build_conn()
    |> Map.put(:host, "preview.localhost")
    |> get(path)
  end
end
