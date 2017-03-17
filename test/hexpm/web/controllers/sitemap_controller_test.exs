defmodule Hexpm.Web.SitemapControllerTest do
  use Hexpm.ConnCase, async: true

  setup do
    package = insert(:package, updated_at: ~N[2014-04-17 14:00:00.000])
    %{package: package}
  end

  test "GET /sitemap.xml", %{package: package} do
    conn = get build_conn(), "/sitemap.xml"
    sitemap = read_fixture("sitemap.xml") |> String.replace("{package}", package.name)
    assert response(conn, 200) == sitemap
  end
end
