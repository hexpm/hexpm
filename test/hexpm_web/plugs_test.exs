defmodule HexpmWeb.PlugsTest do
  use HexpmWeb.ConnCase, async: true

  alias HexpmWeb.Plugs

  @max_body_size 20 * 1024 * 1024

  describe "fetch_body/2" do
    test "writes a body at the size limit to a file" do
      conn = Plugs.fetch_body(upload_conn(@max_body_size), [])

      assert File.stat!(conn.params["body"]).size == @max_body_size
    end

    test "rejects a body that goes past the size limit in its last chunk" do
      conn = upload_conn(@max_body_size + 1)

      assert_raise Plug.Parsers.RequestTooLargeError, fn -> Plugs.fetch_body(conn, []) end
    end
  end

  defp upload_conn(size) do
    conn = build_conn(:post, "/api/publish", :binary.copy("a", size))
    %{conn | params: %{}}
  end
end
