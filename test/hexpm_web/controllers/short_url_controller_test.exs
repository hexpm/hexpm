defmodule HexpmWeb.ShortURLControllerTest do
  use HexpmWeb.ConnCase, async: true

  test "show a valid short code" do
    insert(:short_url, url: "https://diff.hex.pm?diff[]=ecto:3.0.0:3.0.1", short_code: "AaBbC")
    conn = get(build_conn(), "/l/AaBbC")
    assert redirected_to(conn, 301) == "https://diff.hex.pm?diff[]=ecto:3.0.0:3.0.1"
  end

  test "show an invalid short code" do
    conn = get(build_conn(), "/l/f4k3")
    assert response(conn, 404)
  end

  # Rows predating the host validation, or written by anything but the
  # changeset, are checked again on the way out rather than redirected to.
  test "does not redirect to a stored URL that fails validation" do
    insert(:short_url, url: "https://evil.example\\@hex.pm/", short_code: "DdEeF")
    conn = get(build_conn(), "/l/DdEeF")
    assert response(conn, 404)
  end
end
