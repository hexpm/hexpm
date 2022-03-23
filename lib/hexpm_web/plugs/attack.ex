# TODO: Don't rate limit conditional requests that return 304 Not Modified

defmodule HexpmWeb.Plugs.Attack do
  use PlugAttack
  import HexpmWeb.ControllerHelpers
  import Plug.Conn
  alias Hexpm.BlockAddress
  alias HexpmWeb.RateLimitPubSub

  @storage {PlugAttack.Storage.Ets, HexpmWeb.Plugs.Attack.Storage}

  rule "allow local", conn do
    allow(conn.remote_ip == {127, 0, 0, 1})
  end

  rule "allow addresses", conn do
    BlockAddress.try_reload()
    allow(BlockAddress.allowed?(ip_string(conn.remote_ip)))
  end

  rule "block addresses", conn do
    BlockAddress.try_reload()
    block(BlockAddress.blocked?(ip_string(conn.remote_ip)))
  end

  rule "user throttle", conn do
    user = conn.assigns[:current_user]

    if api?(conn) && user do
      user_throttle(user.id)
    end
  end

  rule "organization throttle", conn do
    organization = conn.assigns[:current_organization]

    if api?(conn) && organization do
      organization_throttle(organization.id)
    end
  end

  rule "ip throttle", conn do
    if api?(conn) do
      ip_throttle(conn.remote_ip)
    end
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
    |> render_error(429, message: "API rate limit exceeded for #{throttled_user(conn)}")
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

  defp throttled_user(conn) do
    cond do
      user = conn.assigns.current_user ->
        "user #{user.id}"

      organization = conn.assigns.current_organization ->
        "organization #{organization.id}"

      true ->
        "IP #{ip_string(conn.remote_ip)}"
    end
  end

  defp ip_string({a, b, c, d}) do
    "#{a}.#{b}.#{c}.#{d}"
  end

  def user_throttle(user_id, opts \\ []) do
    key = {:user, user_id}
    time = opts[:time] || System.system_time(:millisecond)
    unless opts[:time], do: RateLimitPubSub.broadcast(key, time)

    timed_throttle(
      key,
      time: time,
      storage: @storage,
      limit: 500,
      period: 60_000
    )
  end

  def organization_throttle(organization_id, opts \\ []) do
    key = {:organization, organization_id}
    time = opts[:time] || System.system_time(:millisecond)
    unless opts[:time], do: RateLimitPubSub.broadcast(key, time)

    timed_throttle(
      key,
      time: time,
      storage: @storage,
      limit: 500,
      period: 60_000
    )
  end

  def ip_throttle(ip, opts \\ []) do
    key = {:ip, ip}
    time = opts[:time] || System.system_time(:millisecond)
    unless opts[:time], do: RateLimitPubSub.broadcast(key, time)

    timed_throttle(
      key,
      time: time,
      storage: @storage,
      limit: 100,
      period: 60_000
    )
  end

  # From https://github.com/michalmuskala/plug_attack/blob/812ff857d0958f1a00a711273887d7187ae80a23/lib/rule.ex#L62
  # Adding an option for `now`
  defp timed_throttle(key, opts) do
    if key do
      do_throttle(key, opts)
    else
      nil
    end
  end

  defp do_throttle(key, opts) do
    storage = Keyword.fetch!(opts, :storage)
    limit = Keyword.fetch!(opts, :limit)
    period = Keyword.fetch!(opts, :period)
    now = Keyword.fetch!(opts, :time)

    expires_at = expires_at(now, period)
    count = do_throttle(storage, key, now, period, expires_at)
    rem = limit - count
    data = [period: period, expires_at: expires_at, limit: limit, remaining: max(rem, 0)]
    {if(rem >= 0, do: :allow, else: :block), {:throttle, data}}
  end

  defp expires_at(now, period), do: (div(now, period) + 1) * period

  defp do_throttle({mod, opts}, key, now, period, expires_at) do
    full_key = {:throttle, key, div(now, period)}
    mod.increment(opts, full_key, 1, expires_at)
  end

  defp api?(%Plug.Conn{request_path: "/api/" <> _}), do: true
  defp api?(%Plug.Conn{}), do: false
end
