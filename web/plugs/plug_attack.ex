# TODO: Don't rate limit conditional requests that return 304 Not Modified
# TODO: Add a higher rate limit cap for authenticated users
# TODO: Use redis instead of single process to support multiple dynos

defmodule HexWeb.PlugAttack do
  use PlugAttack

  alias HexWeb.BlockAddress

  import HexWeb.ControllerHelpers
  import Plug.Conn

  rule "allow local", conn do
    allow conn.remote_ip == {127, 0, 0, 1}
  end

  rule "block addresses", conn do
    BlockAddress.try_reload()
    block BlockAddress.blocked?(ip_str(conn.remote_ip))
  end

  rule "ip throttle", conn do
    throttle(conn.remote_ip, [storage: {PlugAttack.Storage.Ets, HexWeb.PlugAttack},
                              limit: 100, period: 60_000])
  end

  def allow_action(conn, {:throttle, data}, _opts) do
    add_throttling_headers(conn, data)
  end

  def allow_action(conn, _data, _opts) do
    conn
  end

  def block_action(conn, {:throttle, data}, _opts) do
    conn
    |> add_throttling_headers(data)
    |> render_error(429, message: "API rate limit exceeded for #{ip_str(conn.remote_ip)}")
  end

  def block_action(conn, _data, _opts) do
    render_error(conn, 403, message: "Blocked")
  end

  defp add_throttling_headers(conn, data) do
    # The expires_at value is a unix time in milliseconds, we want to return one
    # in seconds
    reset = div(data[:expires_at], 1_000)
    conn
    |> put_resp_header("x-ratelimit-limit", Integer.to_string(data[:limit]))
    |> put_resp_header("x-ratelimit-remaining", Integer.to_string(data[:remaining]))
    |> put_resp_header("x-ratelimit-reset", Integer.to_string(reset))
  end

  defp ip_str({a, b, c, d}) do
    "#{a}.#{b}.#{c}.#{d}"
  end
end
