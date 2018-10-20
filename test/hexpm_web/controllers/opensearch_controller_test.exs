defmodule HexpmWeb.OpenSearchControllerTest do
  use HexpmWeb.ConnCase, async: true

  test "opensearch" do
    conn = get(build_conn(), "/hexsearch.xml")

    assert response(conn, 200) =~
             "<Url type=\"text/html\" method=\"get\" template=\"http://localhost:5000/packages?search={searchTerms}&amp;sort=recent_downloads\" />"
  end
end
