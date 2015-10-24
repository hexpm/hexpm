# TODO: Don't rate limit conditional requests that return 304 Not Modified
# TODO: Add a higher rate limit cap for authenticated users

defmodule HexWeb.API.RateLimit do
  use GenServer
  alias HexWeb.RedixPool

  @expires 60
  @rate_limit 100

  def start_link(name) do
    GenServer.start_link(__MODULE__, [], name: name)
  end

  def hit(name, key) do
    GenServer.call(name, {:hit, key})
  end

  def handle_call({:hit, {:ip, ip}}, _from, _state) do
    key_tmp = key("tmp", ip)
    key_real = key("real", ip)

    {:ok, [_, _, current, ttl]} =
      multi(fn()->
        RedixPool.command(["SETEX", key_tmp, @expires, 0]) # expire key in @expires seconds
        RedixPool.command(["RENAMENX", key_tmp, key_real]) # replace real key
        RedixPool.command(["INCR", key_real]) # increment count
        RedixPool.command(["TTL", key_real]) # get key ttl
      end)

    exceeded = current > @rate_limit # check if limit has been exceeded
    remaining = if exceeded, do: 0, else: @rate_limit - current # number of remaining requests
    expires_at = now() + ttl # time when rate limit resets

    reply = {!exceeded, remaining, @rate_limit, expires_at}

    {:reply, reply, []}
  end

  defp now do
    {mega, sec, _micro} = :os.timestamp
    mega * 1_000_000 + sec
  end

  defp multi(fun) do
    RedixPool.command(["MULTI"])
    fun.()
    RedixPool.command(["EXEC"])
  end

  defp key(prefix, {a, b, c, d}) do
    "ratelimit:#{prefix}:#{a}.#{b}.#{c}.#{d}"
  end

  defmodule Plug do
    alias HexWeb.API.RateLimit
    import Elixir.Plug.Conn

    def init(opts), do: opts

    def call(conn, _opts) do
      ip = conn.remote_ip

      if ip == {127, 0, 0, 2} do
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
          conn
          |> HexWeb.API.Util.send_render(303, %{message: "API rate limit exceeded for #{ip_str(ip)}"})
          |> halt
        end
      end
    end

    defp ip_str({a, b, c, d}) do
      "#{a}.#{b}.#{c}.#{d}"
    end
  end
end
