# TODO: Don't rate limit conditional requests that return 304 Not Modified

defmodule HexpmWeb.Plugs.Attack do
  use PlugAttack
  import HexpmWeb.ControllerHelpers
  import Plug.Conn
  alias Hexpm.BlockAddress
  alias HexpmWeb.RateLimitPubSub

  @storage {PlugAttack.Storage.Ets, HexpmWeb.Plugs.Attack.Storage}
  # Limits with few requests that have to hold across pods and deploys count in
  # the database, where every pod shares the count and a deploy doesn't reset it.
  @database_storage {Hexpm.RateLimits, []}
  @diff_limit 20
  @diff_period 60_000
  @sso_period 10 * 60_000
  @short_url_period 10 * 60_000

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

  rule "workload identity throttle", conn do
    workload_identity = conn.assigns[:workload_identity]

    if api?(conn) && workload_identity do
      workload_identity_throttle(workload_identity.id)
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

  rule "workload identity mint ip throttle", conn do
    if workload_identity_mint?(conn) do
      workload_identity_mint_ip_throttle(conn.remote_ip)
    end
  end

  rule "ip throttle", conn do
    if api?(conn) and not workload_identity_mint?(conn) and not oidc_audience?(conn) do
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

      workload_identity = conn.assigns[:workload_identity] ->
        "workload identity #{workload_identity.id}"

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

  def workload_identity_throttle(workload_identity_id, opts \\ []) do
    key = {:workload_identity, workload_identity_id}
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

  @doc """
  Checks an address before `HexpmWeb.Plugs.authenticate/2` looks at the
  credential it sent. A blocked address, and one whose credentials were
  refused more than `authentication_failure_ip_throttle/2` allows, are refused
  without their credential being checked.
  """
  def check_authentication(ip) do
    BlockAddress.try_reload()
    address = ip_string(ip)

    cond do
      ip == {127, 0, 0, 1} or BlockAddress.allowed?(address) ->
        :ok

      BlockAddress.blocked?(address) ->
        {:error, :blocked}

      throttled?(authentication_failure_ip_throttle(ip, increment: 0)) ->
        {:error, :authentication_rate_limited}

      true ->
        :ok
    end
  end

  # Counts the API credentials refused from an address. Only a refusal is
  # broadcast, since the other pods count every message they receive.
  def authentication_failure_ip_throttle(ip, opts \\ []) do
    key = {:authentication_failure_ip, ip}
    time = opts[:time] || System.system_time(:millisecond)
    increment = Keyword.get(opts, :increment, 1)
    if !opts[:time] and increment > 0, do: RateLimitPubSub.broadcast(key, time)

    timed_throttle(
      key,
      time: time,
      increment: increment,
      storage: @storage,
      limit: 100,
      period: 60_000
    )
  end

  defp throttled?({:block, _data}), do: true
  defp throttled?(_result), do: false

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

  # Counts the uses of a Varsel token id until the token expires at
  # `expires_at`, in unix seconds, after which the token is refused anyway.
  def varsel_jti(jti, expires_at) do
    {storage, opts} = @database_storage
    storage.increment(opts, {:varsel_jti, jti}, 1, expires_at * 1_000)
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

  # Counts only requests that would write a new short URL; a link that
  # already has one is answered without touching the bucket. Not broadcast,
  # so each pod keeps its own count.
  def short_url_ip_throttle(ip, opts \\ []) do
    key = {:short_url_ip, ip}
    time = opts[:time] || System.system_time(:millisecond)

    timed_throttle(
      key,
      time: time,
      storage: @storage,
      limit: 30,
      period: @short_url_period
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
      increment: Keyword.get(opts, :increment, 1),
      storage: @database_storage,
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

  def workload_identity_mint_throttle(key, opts \\ []) do
    time = opts[:time] || System.system_time(:millisecond)
    unless opts[:time], do: RateLimitPubSub.broadcast({:workload_identity_mint, key}, time)

    timed_throttle(
      {:workload_identity_mint, key},
      time: time,
      increment: Keyword.get(opts, :increment, 1),
      storage: @storage,
      limit: 30,
      period: 15 * 60_000
    )
  end

  # CI runners can share an address, so this sits far above what a pool of
  # runners exchanges. It bounds what one address can send, including replays of
  # a used OIDC token, which the per-repository limit doesn't count.
  def workload_identity_mint_ip_throttle(ip, opts \\ []) do
    key = {:workload_identity_mint_ip, ip}
    time = opts[:time] || System.system_time(:millisecond)
    unless opts[:time], do: RateLimitPubSub.broadcast(key, time)

    timed_throttle(
      key,
      time: time,
      storage: @storage,
      limit: 1_000,
      period: 60_000
    )
  end

  def workload_identity_mint_blocked?(key) do
    {_, {:throttle, data}} =
      workload_identity_mint_throttle(key, time: System.system_time(:millisecond), increment: 0)

    data[:remaining] == 0
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
      storage: @database_storage,
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
      storage: @database_storage,
      limit: 5,
      period: 10 * 60_000
    )
  end

  def device_verification_user_throttle(user_id, opts \\ []) do
    time = opts[:time] || System.system_time(:millisecond)

    timed_throttle(
      {:device_verification_user, user_id},
      time: time,
      storage: @database_storage,
      limit: 10,
      period: 15 * 60_000
    )
  end

  def device_verification_ip_throttle(ip, opts \\ []) do
    time = opts[:time] || System.system_time(:millisecond)

    timed_throttle(
      {:device_verification_ip, ip},
      time: time,
      storage: @database_storage,
      limit: 30,
      period: 15 * 60_000
    )
  end

  @spec account_delete_request_throttle(integer(), keyword()) ::
          {:allow | :block, {:throttle, keyword()}}
  # Adding a workload identity looks the repository up on GitHub with the OAuth
  # app's credentials, whose quota every add on Hex shares.
  def workload_identity_lookup_throttle(user_id, opts \\ []) do
    key = {:workload_identity_lookup, user_id}
    time = opts[:time] || System.system_time(:millisecond)
    unless opts[:time], do: RateLimitPubSub.broadcast(key, time)

    timed_throttle(
      key,
      time: time,
      storage: @storage,
      limit: 20,
      period: 60 * 60_000
    )
  end

  def account_delete_request_throttle(user_id, opts \\ []) do
    time = opts[:time] || System.system_time(:millisecond)

    timed_throttle(
      {:account_delete_request, user_id},
      time: time,
      storage: @database_storage,
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
      storage: @database_storage,
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
      storage: @database_storage,
      limit: 5,
      period: 15 * 60_000
    )
  end

  defp api?(conn), do: match?(["api" | _], routed_path(conn))

  # Verified failed mints have their own limit, keyed on the repository that
  # signed the token, in HexpmWeb.API.OAuthController.
  defp workload_identity_mint?(%Plug.Conn{params: %{"grant_type" => grant_type}} = conn) do
    grant_type == "urn:ietf:params:oauth:grant-type:jwt-bearer" and
      routed_path(conn) == ["api", "oauth", "token"]
  end

  defp workload_identity_mint?(%Plug.Conn{}), do: false

  defp oidc_audience?(%Plug.Conn{method: "GET"} = conn),
    do: routed_path(conn) == ["api", "oidc", "audience"]

  defp oidc_audience?(%Plug.Conn{}), do: false

  defp scim?(conn), do: match?(["scim" | _], routed_path(conn))

  # path_info has no empty segments and the router matches each one decoded,
  # so /%61pi/users/me and //api/users/me are API routes too.
  defp routed_path(conn), do: Enum.map(conn.path_info, &URI.decode/1)
end
