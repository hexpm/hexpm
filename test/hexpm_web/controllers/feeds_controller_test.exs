defmodule HexpmWeb.FeedsControllerTest do
  use HexpmWeb.ConnCase, async: true

  test "GET /feeds/blog.xml" do
    conn = get(build_conn(), "/feeds/blog.xml")

    assert conn.status == 200
    assert get_resp_header(conn, "content-type") == ["application/rss+xml; charset=utf-8"]
    assert String.starts_with?(conn.resp_body, "<?xml version=\"1.0\" encoding=\"utf-8\"?>")
    assert conn.resp_body =~ "Private packages and organizations"
  end
end
