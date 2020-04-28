defmodule HexpmWeb.ShortURLControllerTest do
  use HexpmWeb.ConnCase, async: true

  test "show a valid short code" do
    insert(:short_url, url: "https://diff.hex.pm?diff[]=ecto:3.0.0:3.0.1", short_code: "AaBbC")
    conn = get(build_conn(), "l/AaBbC")
    assert redirected_to(conn, 301) == "https://diff.hex.pm?diff[]=ecto:3.0.0:3.0.1"
  end

  test "show an invalid short code" do
    conn = get(build_conn(), "l/f4k3")
    assert response(conn, 404)
  end
end
