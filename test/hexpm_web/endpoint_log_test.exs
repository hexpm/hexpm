defmodule HexpmWeb.EndpointLogTest do
  use HexpmWeb.ConnCase
  import ExUnit.CaptureLog

  setup do
    level = Logger.level()
    Logger.configure(level: :info)
    on_exit(fn -> Logger.configure(level: level) end)
  end

  test "logs one line per request" do
    log = capture_log(fn -> get(build_conn(), "/diffs") end)

    assert [line] = String.split(log, "\n", trim: true)
    assert line =~ ~r"^\[info\] .*\bstatus=200\b.*\bpath=/diffs\b.*\bmethod=GET\b"
  end
end
