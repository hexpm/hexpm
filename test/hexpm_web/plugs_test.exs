defmodule HexpmWeb.PlugsTest do
  use HexpmWeb.ConnCase, async: true

  alias HexpmWeb.Plugs

  @max_body_size 20 * 1024 * 1024

  describe "read_body_to_file/1" do
    test "writes a body at the size limit to a file" do
      {_conn, path} = Plugs.read_body_to_file(upload_conn(@max_body_size))

      assert File.stat!(path).size == @max_body_size
    end

    test "rejects a body that goes past the size limit in its last chunk" do
      conn = upload_conn(@max_body_size + 1)

      assert_raise Plug.Parsers.RequestTooLargeError, fn -> Plugs.read_body_to_file(conn) end
    end
  end

  describe "default_repository/2" do
    test "defaults the repository on the paths the router matches decoded" do
      for path <- ["/%61pi/publish", "/api/%70ackages/ecto", "/%70ackages/ecto"] do
        conn = Plugs.default_repository(Plug.Test.conn(:get, path, %{}), [])
        assert conn.params["repository"] == "hexpm", path
      end
    end
  end

  describe "authenticate/2" do
    setup do
      align_to_throttle_bucket()
      %{user: insert(:user)}
    end

    test "refuses an address whose credentials were refused 100 times this minute", %{
      user: user
    } do
      ip = {203, 0, 113, 125}

      for _ <- 1..100 do
        assert api_request(ip, "0123456789abcdef0123456789abcdef").status == 401
      end

      conn = api_request(ip, "0123456789abcdef0123456789abcdef")
      assert json_response(conn, 429)["message"] =~ "Too many failed authentication attempts"

      lines = capture_log_lines(fn -> assert api_request(ip, key_for(user)).status == 429 end)
      refute Enum.any?(lines, fn {_level, fields} -> fields[:event] == "auth.failure" end)
    end

    test "counts refused Bearer tokens", %{user: user} do
      ip = {203, 0, 113, 126}

      for _ <- 1..100, do: assert(api_request(ip, "Bearer invalid").status == 401)

      assert api_request(ip, "Bearer invalid").status == 429
      assert api_request(ip, key_for(user)).status == 429
    end

    test "doesn't refuse requests without credentials" do
      ip = {203, 0, 113, 127}

      for _ <- 1..101, do: api_request(ip, "0123456789abcdef0123456789abcdef")

      conn = get(%{build_conn() | remote_ip: ip}, ~p"/api/packages")
      assert conn.status == 200
    end

    test "doesn't count accepted credentials", %{user: user} do
      ip = {203, 0, 113, 128}
      key = key_for(user)

      for _ <- 1..101, do: assert(api_request(ip, key).status == 200)
      assert api_request(ip, "0123456789abcdef0123456789abcdef").status == 401
    end
  end

  defp api_request(ip, authorization) do
    %{build_conn() | remote_ip: ip}
    |> put_req_header("authorization", authorization)
    |> get(~p"/api/users/me")
  end

  defp upload_conn(size) do
    conn = build_conn(:post, "/api/publish", :binary.copy("a", size))
    %{conn | params: %{}}
  end
end
