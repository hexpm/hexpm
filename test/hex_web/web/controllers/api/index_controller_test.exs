defmodule HexWeb.API.IndexControllerTest do
  use HexWeb.ConnCase, async: true

  test "index" do
    conn = get build_conn(), "/api"

    assert json_response(conn, 200)["package_url"] =~ "/api/packages/{name}"
  end
end
