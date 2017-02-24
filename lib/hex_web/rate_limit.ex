# TODO: Don't rate limit conditional requests that return 304 Not Modified
# TODO: Add a higher rate limit cap for authenticated users
# TODO: Use redis instead of single process to support multiple dynos

defmodule HexWeb.RateLimit do
  use GenServer

  @compile {:parse_transform, :ms_transform}

  @prune_timer 60_000
  @expires 60
  @rate_limit 100

  def start_link(name) do
    GenServer.start_link(__MODULE__, name, name: name)
  end

  def prune(name, expires) do
    GenServer.call(name, {:prune, expires})
  end

  def hit(name, key) do
    now = now()

    [count, created_at] =
      if :ets.insert_new(name, {key, 1, now}) do
        [1, now]
      else
        :ets.update_counter(name, key, [{2, 1}, {3, 0}])
      end

    expires_at = created_at + @expires

    if expires_at <= now do
      :ets.insert_new(name, {key, 1, now})
      {true, @rate_limit - 1, @rate_limit, now + @expires}
    else
      remaining = @rate_limit - count
      {remaining >= 0, max(remaining, 0), @rate_limit, expires_at}
    end
  end

  def init(name) do
    :ets.new(name, [:named_table, :set, :public, read_concurrency: true, write_concurrency: true])
    :erlang.send_after(@prune_timer, self(), {:prune_timer, @expires})
    {:ok, name}
  end

  def handle_call({:prune, expires}, _from, name) do
    do_prune(expires, name)
    {:reply, :ok, name}
  end

  def handle_info({:prune_timer, expires}, name) do
    do_prune(expires, name)
    {:noreply, name}
  end

  defp do_prune(expires, name) do
    delete_at = now() - expires
    ms = :ets.fun2ms(fn {_,_,created_at} -> created_at <= delete_at end)

    :ets.select_delete(name, ms)
    :erlang.send_after(@prune_timer, self(), {:prune_timer, expires})
  end

  defp now do
    {mega, sec, _micro} = :os.timestamp
    mega * 1_000_000 + sec
  end

  defmodule Plug do
    alias HexWeb.RateLimit
    import Elixir.Plug.Conn
    import HexWeb.ControllerHelpers

    @behaviour Elixir.Plug

    def init(opts), do: opts

    def call(conn, _opts) do
      ip = conn.remote_ip

      if ip == {127, 0, 0, 1} do
        conn
      else
        {allowed, remaining, limit, reset} = RateLimit.hit(RateLimit, {:ip, ip})

        conn =
          conn
          |> put_resp_header("x-ratelimit-limit", Integer.to_string(limit))
          |> put_resp_header("x-ratelimit-remaining", Integer.to_string(remaining))
          |> put_resp_header("x-ratelimit-reset", Integer.to_string(reset))

        if allowed do
          conn
        else
          render_error(conn, 429, message: "API rate limit exceeded for #{ip_str(ip)}")
        end
      end
    end

    defp ip_str({a, b, c, d}) do
      "#{a}.#{b}.#{c}.#{d}"
    end
  end
end
