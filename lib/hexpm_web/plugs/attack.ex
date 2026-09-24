# TODO: Don't rate limit conditional requests that return 304 Not Modified

defmodule HexpmWeb.Plugs.Attack do
  use PlugAttack
  import HexpmWeb.ControllerHelpers
  import Plug.Conn
  alias Hexpm.BlockAddress
  alias HexpmWeb.RateLimitPubSub

  @storage {PlugAttack.Storage.Ets, HexpmWeb.Plugs.Attack.Storage}
  @diff_limit 20
  @diff_period 60_000
  @sso_period 10 * 60_000
  @varsel_jti_period 300_000

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
      allow(user.service) || user_throttle(user.id)
    end
  end

  rule "organization throttle", conn do
    organization = conn.assigns[:current_organization]

    if api?(conn) && organization do
      organization_throttle(organization.id)
    end
  end

  # The provisioning agent is one client per connection whatever address it
  # sends from, and the address is the provider's shared egress, so the
  # connection is the key. Requests that fail authentication never reach here.
  rule "scim connection throttle", conn do
    connection = conn.assigns[:scim_connection]

    if scim?(conn) && connection do
      scim_connection_throttle(connection.id)
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
    |> put_retry_after(data)
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

  # The standard header for a 429, which the provisioning agents read to pace
  # their retries; the x-ratelimit headers are ours.
  defp put_retry_after(conn, data) do
    seconds = max(div(data[:expires_at] - System.system_time(:millisecond) + 999, 1_000), 1)
    put_resp_header(conn, "retry-after", Integer.to_string(seconds))
  end

  defp throttled_user(conn) do
    cond do
      user = conn.assigns[:current_user] ->
        "user #{user.id}"

      organization = conn.assigns[:current_organization] ->
        "organization #{organization.id}"

      connection = conn.assigns[:scim_connection] ->
        "provisioning connection #{connection.id}"

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

  # The same budget an authenticated organization gets on the API. A provider
  # sends two or three requests per person it touches and fans them out, so
  # a bulk unassignment or an initial import runs well past the address limit.
  def scim_connection_throttle(connection_id, opts \\ []) do
    key = {:scim_connection, connection_id}
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

  def varsel_jti(jti, opts \\ []) do
    key = {:varsel_jti, jti}
    time = opts[:time] || System.system_time(:millisecond)
    unless opts[:time], do: RateLimitPubSub.broadcast(key, time)

    {storage, name} = @storage
    storage.increment(name, key, 1, time + @varsel_jti_period)
  end

  def diff_throttle(identity, opts \\ []) do
    key = {:diff, identity}
    time = opts[:time] || System.system_time(:millisecond)
    unless opts[:time], do: RateLimitPubSub.broadcast(key, time)

    timed_throttle(
      key,
      time: time,
      storage: @storage,
      limit: @diff_limit,
      period: @diff_period
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
    increment = Keyword.get(opts, :increment, 1)

    expires_at = expires_at(now, period)
    count = do_throttle(storage, key, now, period, expires_at, increment)
    rem = limit - count
    data = [period: period, expires_at: expires_at, limit: limit, remaining: max(rem, 0)]
    {if(rem >= 0, do: :allow, else: :block), {:throttle, data}}
  end

  defp expires_at(now, period), do: (div(now, period) + 1) * period

  defp do_throttle({mod, opts}, key, now, period, expires_at, increment) do
    full_key = {:throttle, key, div(now, period)}
    mod.increment(opts, full_key, increment, expires_at)
  end

  def login_ip_throttle(ip, opts \\ []) do
    time = opts[:time] || System.system_time(:millisecond)

    timed_throttle(
      {:login_ip, ip},
      time: time,
      storage: @storage,
      limit: 10,
      period: 15 * 60_000
    )
  end

  # The account is what an SSO login belongs to, so it is what the limit is for.
  # The IP bucket below stays as a ceiling on anonymous starts and on one host
  # working through accounts, at a limit an office or a university behind one
  # address does not reach.
  def sso_start_user_throttle(user_id, organization_id, opts \\ []) do
    time = opts[:time] || System.system_time(:millisecond)
    key = {:sso_start_user, user_id, organization_id}
    unless opts[:time], do: RateLimitPubSub.broadcast(key, time)

    timed_throttle(
      key,
      time: time,
      storage: @storage,
      limit: 20,
      period: @sso_period
    )
  end

  def sso_start_ip_throttle(ip, opts \\ []) do
    time = opts[:time] || System.system_time(:millisecond)
    unless opts[:time], do: RateLimitPubSub.broadcast({:sso_start_ip, ip}, time)

    timed_throttle(
      {:sso_start_ip, ip},
      time: time,
      storage: @storage,
      limit: 300,
      period: @sso_period
    )
  end

  def sso_start_organization_throttle(organization_id, ip, opts \\ []) do
    time = opts[:time] || System.system_time(:millisecond)
    key = {:sso_start_organization, organization_id, ip}
    unless opts[:time], do: RateLimitPubSub.broadcast(key, time)

    timed_throttle(
      key,
      time: time,
      storage: @storage,
      limit: 20,
      period: @sso_period
    )
  end

  def sso_callback_ip_throttle(ip, opts \\ []) do
    time = opts[:time] || System.system_time(:millisecond)
    unless opts[:time], do: RateLimitPubSub.broadcast({:sso_callback_ip, ip}, time)

    timed_throttle(
      {:sso_callback_ip, ip},
      time: time,
      storage: @storage,
      limit: 50,
      period: @sso_period
    )
  end

  def tfa_ip_throttle(ip, opts \\ []) do
    time = opts[:time] || System.system_time(:millisecond)

    timed_throttle(
      {:tfa_ip, ip},
      time: time,
      increment: Keyword.get(opts, :increment, 1),
      storage: @storage,
      limit: 20,
      period: 15 * 60_000
    )
  end

  def tfa_user_throttle(user_id, opts \\ []) do
    time = opts[:time] || System.system_time(:millisecond)

    timed_throttle(
      {:tfa_user, user_id},
      time: time,
      increment: Keyword.get(opts, :increment, 1),
      storage: @storage,
      limit: 5,
      period: 10 * 60_000
    )
  end

  def device_verification_user_throttle(user_id, opts \\ []) do
    time = opts[:time] || System.system_time(:millisecond)

    timed_throttle(
      {:device_verification_user, user_id},
      time: time,
      storage: @storage,
      limit: 10,
      period: 15 * 60_000
    )
  end

  def device_verification_ip_throttle(ip, opts \\ []) do
    time = opts[:time] || System.system_time(:millisecond)

    timed_throttle(
      {:device_verification_ip, ip},
      time: time,
      storage: @storage,
      limit: 30,
      period: 15 * 60_000
    )
  end

  @spec account_delete_request_throttle(integer(), keyword()) ::
          {:allow | :block, {:throttle, keyword()}}
  def account_delete_request_throttle(user_id, opts \\ []) do
    time = opts[:time] || System.system_time(:millisecond)

    timed_throttle(
      {:account_delete_request, user_id},
      time: time,
      storage: @storage,
      limit: 3,
      period: 60 * 60_000
    )
  end

  @spec sudo_password_throttle(integer(), keyword()) :: {:allow | :block, {:throttle, keyword()}}
  def sudo_password_throttle(user_id, opts \\ []) do
    time = opts[:time] || System.system_time(:millisecond)

    timed_throttle(
      {:sudo_password, user_id},
      time: time,
      storage: @storage,
      limit: 5,
      period: 15 * 60_000
    )
  end

  @spec sudo_tfa_throttle(integer(), keyword()) :: {:allow | :block, {:throttle, keyword()}}
  def sudo_tfa_throttle(user_id, opts \\ []) do
    time = opts[:time] || System.system_time(:millisecond)

    timed_throttle(
      {:sudo_tfa, user_id},
      time: time,
      storage: @storage,
      limit: 5,
      period: 15 * 60_000
    )
  end

  defp api?(%Plug.Conn{request_path: "/api/" <> _}), do: true
  defp api?(%Plug.Conn{}), do: false

  defp scim?(%Plug.Conn{request_path: "/scim/" <> _}), do: true
  defp scim?(%Plug.Conn{}), do: false
end
