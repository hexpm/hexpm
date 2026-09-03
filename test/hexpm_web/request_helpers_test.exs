defmodule HexpmWeb.RequestHelpersTest do
  use HexpmWeb.ConnCase, async: true

  alias HexpmWeb.RequestHelpers

  test "build_usage_info/1 truncates the user agent to 255 bytes" do
    conn = put_req_header(build_conn(), "user-agent", "Mozilla/5.0 " <> combining_string(1000))
    usage_info = RequestHelpers.build_usage_info(conn)

    assert byte_size(usage_info.user_agent) <= 255
    assert String.valid?(usage_info.user_agent)
    assert String.starts_with?(usage_info.user_agent, "Mozilla/5.0 ")
  end

  test "build_usage_info/1 leaves a short user agent alone" do
    conn = put_req_header(build_conn(), "user-agent", "hex/2.0")
    assert RequestHelpers.build_usage_info(conn).user_agent == "hex/2.0"
  end
end
