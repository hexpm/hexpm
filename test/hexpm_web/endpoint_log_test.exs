defmodule HexpmWeb.EndpointLogTest do
  use HexpmWeb.ConnCase

  test "logs one line per request with its fields" do
    assert [{:info, line}] = capture_log_lines(fn -> get(build_conn(), "/diffs") end)

    assert %{
             message: "HTTP request",
             event: "http.request",
             method: "GET",
             path: "/diffs",
             status: 200,
             duration_us: duration,
             controller: "HexpmWeb.DiffController",
             action: :index,
             format: "html",
             request_id: request_id
           } = line

    assert is_integer(duration)
    assert is_binary(request_id)
  end

  test "logs a response that is not a success with its status" do
    assert [{:info, line}] = capture_log_lines(fn -> get(build_conn(), "/api/no/such/route") end)
    assert %{event: "http.request", path: "/api/no/such/route", status: 404} = line
  end

  test "logs the 500 for a request whose process exits" do
    assert [{:info, line}] =
             capture_log_lines(fn ->
               assert_error_sent(500, fn -> get(build_conn(), "/_test/exit") end)
             end)

    assert %{event: "http.request", path: "/_test/exit", status: 500} = line
  end
end
