defmodule Hexpm.HTTPTest do
  use ExUnit.Case, async: true

  alias Hexpm.HTTP
  alias Plug.Conn

  setup do
    lasso = Lasso.open()
    {:ok, lasso: lasso}
  end

  test "get/2", %{lasso: lasso} do
    Lasso.expect_once(lasso, "GET", "/get", fn conn ->
      Conn.resp(conn, 200, "respbody")
    end)

    assert {:ok, 200, _headers, "respbody"} = HTTP.get(lasso_url(lasso, "/get"), [])
  end

  test "post/3", %{lasso: lasso} do
    Lasso.expect_once(lasso, "POST", "/post", fn conn ->
      {:ok, reqbody, conn} = Conn.read_body(conn)
      assert reqbody == "reqbody"
      Conn.resp(conn, 200, "respbody")
    end)

    assert {:ok, 200, _headers, "respbody"} =
             HTTP.post(lasso_url(lasso, "/post"), [], "reqbody")
  end

  test "put/3", %{lasso: lasso} do
    Lasso.expect_once(lasso, "PUT", "/put", fn conn ->
      {:ok, reqbody, conn} = Conn.read_body(conn)
      assert reqbody == "reqbody"
      Conn.resp(conn, 200, "respbody")
    end)

    assert {:ok, 200, _headers, "respbody"} = HTTP.put(lasso_url(lasso, "/put"), [], "reqbody")
  end

  test "patch/3", %{lasso: lasso} do
    Lasso.expect_once(lasso, "PATCH", "/patch", fn conn ->
      {:ok, reqbody, conn} = Conn.read_body(conn)
      assert reqbody == "reqbody"
      Conn.resp(conn, 200, "respbody")
    end)

    assert {:ok, 200, _headers, "respbody"} =
             HTTP.patch(lasso_url(lasso, "/patch"), [], "reqbody")
  end

  test "delete/2", %{lasso: lasso} do
    Lasso.expect_once(lasso, "DELETE", "/delete", fn conn ->
      Conn.resp(conn, 200, "respbody")
    end)

    assert {:ok, 200, _headers, "respbody"} = HTTP.delete(lasso_url(lasso, "/delete"), [])
  end

  test "post/3 encode json", %{lasso: lasso} do
    Lasso.expect_once(lasso, "POST", "/post", fn conn ->
      {:ok, reqbody, conn} = Conn.read_body(conn)
      assert Jason.decode(reqbody) == {:ok, %{"key" => "value"}}
      Conn.resp(conn, 200, "respbody")
    end)

    headers = [{"content-type", "application/json"}]
    params = %{"key" => "value"}

    assert {:ok, 200, _headers, "respbody"} =
             HTTP.post(lasso_url(lasso, "/post"), headers, params)
  end

  test "post/3 encode urlencoded", %{lasso: lasso} do
    Lasso.expect_once(lasso, "POST", "/post", fn conn ->
      {:ok, reqbody, conn} = Conn.read_body(conn)
      assert URI.decode_query(reqbody) == %{"key" => "value"}
      Conn.resp(conn, 200, "respbody")
    end)

    headers = [{"content-type", "application/x-www-form-urlencoded"}]
    params = %{"key" => "value"}

    assert {:ok, 200, _headers, "respbody"} =
             HTTP.post(lasso_url(lasso, "/post"), headers, params)
  end

  test "get/2 decode json", %{lasso: lasso} do
    Lasso.expect_once(lasso, "GET", "/get", fn conn ->
      conn
      |> Conn.put_resp_header("content-type", "application/json")
      |> Conn.resp(200, Jason.encode!(%{"key" => "value"}))
    end)

    assert {:ok, 200, _headers, %{"key" => "value"}} = HTTP.get(lasso_url(lasso, "/get"), [])
  end

  defp lasso_url(lasso, path) do
    "http://localhost:#{lasso.port}#{path}"
  end
end
