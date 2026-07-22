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

  test "get/3 can stop reading an oversized response", %{lasso: lasso} do
    Lasso.expect_once(lasso, "GET", "/oversized", fn conn ->
      Conn.resp(conn, 200, String.duplicate("x", 100))
    end)

    assert {:error, :response_too_large} =
             HTTP.get(lasso_url(lasso, "/oversized"), [], max_body_bytes: 10)
  end

  test "get/3 can connect to a pinned address while preserving the hostname", %{lasso: lasso} do
    Lasso.expect_once(lasso, "GET", "/pinned", fn conn ->
      assert Conn.get_req_header(conn, "host") == ["localhost:#{lasso.port}"]
      Conn.resp(conn, 200, "pinned-response")
    end)

    assert {:ok, 200, _headers, "pinned-response"} =
             HTTP.get(lasso_url(lasso, "/pinned"), [],
               connect_address: {127, 0, 0, 1},
               connect_hostname: "localhost",
               receive_timeout: 5_000,
               request_timeout: 5_000
             )
  end

  test "get/3 validates the original hostname over a pinned HTTPS connection" do
    {url, cacerts, server} = open_tls_server()

    assert {:ok, 200, _headers, "tls-response"} =
             HTTP.get(url, [],
               connect_address: {127, 0, 0, 1},
               connect_hostname: URI.parse(url).host,
               connect_cacerts: cacerts,
               receive_timeout: 5_000,
               request_timeout: 5_000
             )

    assert :ok = Task.await(server)
  end

  test "get/3 rejects a certificate for a different hostname over a pinned connection" do
    {url, cacerts, server} = open_tls_server()

    assert {:error, %Mint.TransportError{reason: {:tls_alert, _reason}}} =
             HTTP.get(url, [],
               connect_address: {127, 0, 0, 1},
               connect_hostname: "wrong.example.com",
               connect_cacerts: cacerts,
               receive_timeout: 5_000,
               request_timeout: 5_000
             )

    assert :ok = Task.await(server)
  end

  test "get/3 normalizes and closes a pinned Mint request error", %{lasso: lasso} do
    assert {:error, _reason} =
             HTTP.get(lasso_url(lasso, "/invalid-request"), [{"bad\nheader", "value"}],
               connect_address: {127, 0, 0, 1},
               connect_hostname: "localhost",
               receive_timeout: 5_000,
               request_timeout: 5_000
             )
  end

  test "head/2", %{lasso: lasso} do
    Lasso.expect_once(lasso, "HEAD", "/head", fn conn ->
      conn
      |> Conn.put_resp_header("content-length", "8")
      |> Conn.resp(200, "")
    end)

    assert {:ok, 200, headers, ""} = HTTP.head(lasso_url(lasso, "/head"), [])
    assert {"content-length", "8"} in headers
  end

  test "head/3 can return an empty raw json response", %{lasso: lasso} do
    Lasso.expect_once(lasso, "HEAD", "/raw-json", fn conn ->
      conn
      |> Conn.put_resp_header("content-type", "application/json")
      |> Conn.resp(200, "")
    end)

    assert {:ok, 200, _headers, ""} =
             HTTP.head(lasso_url(lasso, "/raw-json"), [], decode_body: false)
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

  test "post/3 accepts iodata", %{lasso: lasso} do
    Lasso.expect_once(lasso, "POST", "/iodata", fn conn ->
      {:ok, reqbody, conn} = Conn.read_body(conn)
      assert reqbody == "iodata"
      Conn.resp(conn, 200, "ok")
    end)

    assert {:ok, 200, _headers, "ok"} =
             HTTP.post(lasso_url(lasso, "/iodata"), [], ["io", ["data"]])
  end

  test "put/3", %{lasso: lasso} do
    Lasso.expect_once(lasso, "PUT", "/put", fn conn ->
      {:ok, reqbody, conn} = Conn.read_body(conn)
      assert reqbody == "reqbody"
      Conn.resp(conn, 200, "respbody")
    end)

    assert {:ok, 200, _headers, "respbody"} = HTTP.put(lasso_url(lasso, "/put"), [], "reqbody")
  end

  @tag :tmp_dir
  test "put_file/3 streams a file", %{lasso: lasso, tmp_dir: tmp_dir} do
    path = Path.join(tmp_dir, "upload.txt")
    File.write!(path, String.duplicate("streamed", 20_000))

    Lasso.expect_once(lasso, "PUT", "/put-file", fn conn ->
      {:ok, body, conn} = Conn.read_body(conn)
      assert body == File.read!(path)
      Conn.resp(conn, 200, "ok")
    end)

    assert {:ok, 200, _headers, "ok"} = HTTP.put_file(lasso_url(lasso, "/put-file"), [], path)
  end

  test "retry keeps transport-only defaults" do
    {:ok, counter} = Agent.start_link(fn -> 0 end)

    assert {:ok, 503, [], "unavailable"} =
             HTTP.retry(
               fn ->
                 Agent.update(counter, &(&1 + 1))
                 {:ok, 503, [], "unavailable"}
               end,
               "default",
               base_delay: 0
             )

    assert Agent.get(counter, & &1) == 1
  end

  test "retry supports configurable attempts and statuses" do
    {:ok, counter} = Agent.start_link(fn -> 0 end)

    assert {:ok, 200, [], "ok"} =
             HTTP.retry(
               fn ->
                 attempt = Agent.get_and_update(counter, &{&1, &1 + 1})
                 if attempt < 4, do: {:ok, 429, [], "limited"}, else: {:ok, 200, [], "ok"}
               end,
               "configured",
               attempts: 5,
               base_delay: 0,
               statuses: [429, 500..599]
             )

    assert Agent.get(counter, & &1) == 5
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
      assert JSON.decode(reqbody) == {:ok, %{"key" => "value"}}
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
      |> Conn.resp(200, JSON.encode!(%{"key" => "value"}))
    end)

    assert {:ok, 200, _headers, %{"key" => "value"}} = HTTP.get(lasso_url(lasso, "/get"), [])
  end

  test "get/3 can return a raw json response", %{lasso: lasso} do
    Lasso.expect_once(lasso, "GET", "/raw-json", fn conn ->
      conn
      |> Conn.put_resp_header("content-type", "application/json")
      |> Conn.resp(200, ~s({"key":"value"}))
    end)

    assert {:ok, 200, _headers, ~s({"key":"value"})} =
             HTTP.get(lasso_url(lasso, "/raw-json"), [], decode_body: false)
  end

  test "passes receive_timeout, pool_timeout, and request_timeout to Finch.request/3", %{
    lasso: lasso
  } do
    Lasso.expect_once(lasso, "GET", "/get", fn conn ->
      Conn.resp(conn, 200, "ok")
    end)

    assert {:ok, 200, _headers, "ok"} =
             HTTP.get(lasso_url(lasso, "/get"), [],
               receive_timeout: 5_000,
               pool_timeout: 5_000,
               request_timeout: 5_000
             )
  end

  defp open_tls_server do
    certificate_options = [key: {:rsa, 2048, 65_537}, digest: :sha256]

    certificate =
      :public_key.pkix_test_data(%{
        root: certificate_options,
        peer: certificate_options
      })

    {:ok, listener} =
      :ssl.listen(0,
        cert: certificate[:cert],
        key: certificate[:key],
        active: false,
        reuseaddr: true
      )

    {:ok, {_address, port}} = :ssl.sockname(listener)
    hostname = :net_adm.localhost() |> to_string()

    server =
      Task.async(fn ->
        with {:ok, socket} <- :ssl.transport_accept(listener),
             {:ok, socket} <- :ssl.handshake(socket, 5_000) do
          {:ok, _request} = :ssl.recv(socket, 0, 5_000)

          :ok =
            :ssl.send(
              socket,
              "HTTP/1.1 200 OK\r\nContent-Length: 12\r\nConnection: close\r\n\r\ntls-response"
            )

          :ssl.close(socket)
        end

        :ssl.close(listener)
        :ok
      end)

    {"https://#{hostname}:#{port}/pinned", certificate[:cacerts], server}
  end

  defp lasso_url(lasso, path) do
    "http://localhost:#{lasso.port}#{path}"
  end
end
