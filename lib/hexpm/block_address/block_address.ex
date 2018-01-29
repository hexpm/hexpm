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
    records =
      Hexpm.BlockAddress.Entry
      |> Hexpm.Repo.all()
      |> Enum.into(MapSet.new(), &{:blocked, &1.ip})

    records = MapSet.put(records, {:allowed, Hexpm.CDN.public_ips()})

    old_records = :ets.tab2list(@ets) |> Enum.map(&elem(&1, 0))

    remove = Enum.reject(old_records, &(&1 in records))
    add = Enum.reject(records, &(&1 in old_records))

    Enum.each(remove, &:ets.delete(@ets, &1))
    :ets.insert(@ets, Enum.map(add, &{&1}))
    :ets.insert(@ets, {:allowed, Hexpm.CDN.public_ips()})
    :ets.insert(@ets, {:loaded, true})
  end

  def blocked?(ip) do
    match?([{{:blocked, ^ip}}], :ets.lookup(@ets, {:blocked, ip}))
  end

  def allowed?(ip) do
    case :ets.lookup(@ets, :allowed) do
      [{:allowed, allowed}] ->
        ip = Hexpm.Utils.parse_ip(ip)
        Hexpm.Utils.in_ip_range?(allowed, ip)

      [] ->
        false
    end
  end
end
