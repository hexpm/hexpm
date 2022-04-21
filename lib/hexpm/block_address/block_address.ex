defmodule Hexpm.BlockAddress do
  @ets :blocked_addresses

  def start() do
    :ets.new(@ets, [:named_table, :set, :public, read_concurrency: true])
    :ets.insert(@ets, {:loaded, false})
  end

  def try_reload() do
    case :ets.lookup(@ets, :loaded) do
      [{:loaded, false}] ->
        reload()

      _ ->
        :ok
    end
  end

  def reload() do
    disallowed =
      Hexpm.BlockAddress.Entry
      |> Hexpm.Repo.all()
      |> Enum.map(&Hexpm.Utils.parse_ip_mask(&1.ip))
      |> Enum.reject(fn {ip, _mask} -> ip == nil end)
      |> Enum.uniq()

    :ets.insert(@ets, {:allowed, Hexpm.CDN.public_ips()})
    :ets.insert(@ets, {:disallowed, disallowed})
    :ets.insert(@ets, {:loaded, true})
  end

  def blocked?(ip) do
    lookup_ip_mask(:disallowed, ip)
  end

  def allowed?(ip) do
    lookup_ip_mask(:allowed, ip)
  end

  defp lookup_ip_mask(key, ip) do
    case :ets.lookup(@ets, key) do
      [{^key, masks}] ->
        ip = Hexpm.Utils.parse_ip(ip)
        Hexpm.Utils.in_ip_range?(masks, ip)

      [] ->
        false
    end
  end
end
