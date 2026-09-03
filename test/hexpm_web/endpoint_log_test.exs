defmodule HexpmWeb.EndpointLogTest do
  use HexpmWeb.ConnCase

  test "logs one line per request with its fields" do
    assert [line] = capture_json_log(fn -> get(build_conn(), "/diffs") end)

    assert %{
             "severity" => "INFO",
             "message" => "GET /diffs 200",
             "method" => "GET",
             "path" => "/diffs",
             "status" => 200,
             "duration_us" => duration,
             "controller" => "HexpmWeb.DiffController",
             "action" => "index",
             "format" => "html",
             "request_id" => request_id
           } = line

    assert is_integer(duration)
    assert is_binary(request_id)
  end

  test "logs a response that is not a success with its status" do
    assert [line] = capture_json_log(fn -> get(build_conn(), "/api/no/such/route") end)

    assert %{"severity" => "INFO", "message" => "GET /api/no/such/route 404", "status" => 404} =
             line
  end
end
