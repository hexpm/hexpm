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
    GenServer.start_link(__MODULE__, [], name: name)
  end

  def init([]) do
    table = :ets.new(:counter, [:set, :private])
    :erlang.send_after(@prune_timer, self(), {:prune_timer, @expires})
    {:ok, table}
  end

  def hit(name, key) do
    GenServer.call(name, {:hit, key})
  end

  def handle_call({:hit, key}, _from, table) do
    now = now()

    [count, created_at] =
      if :ets.insert_new(table, {key, 1, now}) do
        [1, now]
      else
        :ets.update_counter(table, key, [{2, 1}, {3, 0}])
      end

    expires_at = created_at + @expires

    reply =
      if expires_at <= now do
        :ets.insert_new(table, {key, 1, now})
        {true, @rate_limit - 1, @rate_limit, now + @expires}
      else
        remaining = @rate_limit - count
        {remaining >= 0, max(remaining, 0), @rate_limit, expires_at}
      end

    {:reply, reply, table}
  end

  def handle_call(:status, _from, table) do
    {:reply, :ets.tab2list(table), table}
  end

  def handle_info({:prune_timer, expires}, table) do
    delete_at = now() - expires

    ms = fn {_,_,created_at} -> created_at <= delete_at end
         |> :ets.fun2ms

    :ets.select_delete(table, ms)
    :erlang.send_after(@prune_timer, self(), {:prune_timer, expires})
    {:noreply, table}
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
