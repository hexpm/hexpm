defmodule HexWeb.BlockAddress do
  @ets :blocked_addresses

  def start do
    :ets.new(@ets, [:named_table, :set, :public, read_concurrency: true])
    :ets.insert(@ets, {:loaded, false})
  end

  def reload do
    new_ips = HexWeb.Repo.all(HexWeb.BlockedAddress)
              |> Enum.into(HashSet.new, & &1.ip)

    old_ips = :ets.tab2list(@ets) |> Enum.map(&elem(&1, 0))
    removed = Enum.filter(old_ips, &HashSet.member?(new_ips, &1))

    Enum.each(removed, &:ets.delete(@ets, &1))
    :ets.insert(@ets, Enum.map(new_ips, &{&1}))
  end

  defmodule Plug do
    alias HexWeb.BlockAddress
    import Elixir.Plug.Conn
    import Phoenix.Controller

    @ets :blocked_addresses

    def init(opts), do: opts

    def call(conn, _opts) do
      try_reload

      if conn.remote_ip do
        case check(ip(conn.remote_ip)) do
          :ok ->
            conn
            |> put_status(403)
            |> render(HexWeb.ErrorView, :"403", message: "Blocked")
            |> halt
          :error ->
            conn
        end
      else
        conn
      end
    end

    defp try_reload do
      case :ets.lookup(@ets, :loaded) do
        [{:loaded, false}] ->
          BlockAddress.reload
          :ets.insert(@ets, {:loaded, true})
        _ ->
          :ok
      end
    end

    defp check(ip) do
      case :ets.lookup(@ets, ip) do
        [{^ip}] -> :ok
        [] -> :error
      end
    end

    defp ip({a, b, c, d}) do
      "#{a}.#{b}.#{c}.#{d}"
    end
  end
end
