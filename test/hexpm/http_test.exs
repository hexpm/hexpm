defmodule Hexpm.HTTPTest do
  use ExUnit.Case, async: true

  alias Hexpm.HTTP
  alias Plug.Conn

  setup do
    bypass = Bypass.open()
    {:ok, bypass: bypass}
  end

  test "get/2", %{bypass: bypass} do
    Bypass.expect_once(bypass, "GET", "/get", fn conn ->
      Conn.resp(conn, 200, "respbody")
    end)

    assert {:ok, 200, _headers, "respbody"} = HTTP.get(bypass_url(bypass, "/get"), [])
  end

  test "post/3", %{bypass: bypass} do
    Bypass.expect_once(bypass, "POST", "/post", fn conn ->
      {:ok, reqbody, conn} = Conn.read_body(conn)
      assert reqbody == "reqbody"
      Conn.resp(conn, 200, "respbody")
    end)

    assert {:ok, 200, _headers, "respbody"} =
             HTTP.post(bypass_url(bypass, "/post"), [], "reqbody")
  end

  test "put/3", %{bypass: bypass} do
    Bypass.expect_once(bypass, "PUT", "/put", fn conn ->
      {:ok, reqbody, conn} = Conn.read_body(conn)
      assert reqbody == "reqbody"
      Conn.resp(conn, 200, "respbody")
    end)

    assert {:ok, 200, _headers, "respbody"} = HTTP.put(bypass_url(bypass, "/put"), [], "reqbody")
  end

  test "patch/3", %{bypass: bypass} do
    Bypass.expect_once(bypass, "PATCH", "/patch", fn conn ->
      {:ok, reqbody, conn} = Conn.read_body(conn)
      assert reqbody == "reqbody"
      Conn.resp(conn, 200, "respbody")
    end)

    assert {:ok, 200, _headers, "respbody"} =
             HTTP.patch(bypass_url(bypass, "/patch"), [], "reqbody")
  end

  test "delete/2", %{bypass: bypass} do
    Bypass.expect_once(bypass, "DELETE", "/delete", fn conn ->
      Conn.resp(conn, 200, "respbody")
    end)

    assert {:ok, 200, _headers, "respbody"} = HTTP.delete(bypass_url(bypass, "/delete"), [])
  end

  test "post/3 encode json", %{bypass: bypass} do
    Bypass.expect_once(bypass, "POST", "/post", fn conn ->
      {:ok, reqbody, conn} = Conn.read_body(conn)
      assert Jason.decode(reqbody) == {:ok, %{"key" => "value"}}
      Conn.resp(conn, 200, "respbody")
    end)

    headers = [{"content-type", "application/json"}]
    params = %{"key" => "value"}

    assert {:ok, 200, _headers, "respbody"} =
             HTTP.post(bypass_url(bypass, "/post"), headers, params)
  end

  test "post/3 encode urlencoded", %{bypass: bypass} do
    Bypass.expect_once(bypass, "POST", "/post", fn conn ->
      {:ok, reqbody, conn} = Conn.read_body(conn)
      assert URI.decode_query(reqbody) == %{"key" => "value"}
      Conn.resp(conn, 200, "respbody")
    end)

    headers = [{"content-type", "application/x-www-form-urlencoded"}]
    params = %{"key" => "value"}

    assert {:ok, 200, _headers, "respbody"} =
             HTTP.post(bypass_url(bypass, "/post"), headers, params)
  end

  test "get/2 decode json", %{bypass: bypass} do
    Bypass.expect_once(bypass, "GET", "/get", fn conn ->
      conn
      |> Conn.put_resp_header("content-type", "application/json")
      |> Conn.resp(200, Jason.encode!(%{"key" => "value"}))
    end)

    assert {:ok, 200, _headers, %{"key" => "value"}} = HTTP.get(bypass_url(bypass, "/get"), [])
  end

  defp bypass_url(bypass, path) do
    "http://localhost:#{bypass.port}#{path}"
  end
end
