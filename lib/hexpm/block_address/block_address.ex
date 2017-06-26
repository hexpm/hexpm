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
    all_ips =
      Hexpm.BlockAddress.Entry
      |> Hexpm.Repo.all()
      |> Enum.into(MapSet.new, & &1.ip)

    old_ips = :ets.tab2list(@ets) |> Enum.map(&elem(&1, 0))
    old_ips = old_ips -- [:loaded]

    removed = Enum.reject(old_ips, &(&1 in all_ips))
    new_ips = Enum.reject(all_ips, &(&1 in old_ips))

    Enum.each(removed, &:ets.delete(@ets, &1))
    :ets.insert(@ets, Enum.map(new_ips, &{&1}))
    :ets.insert(@ets, {:loaded, true})
  end

  def blocked?(ip) do
    match?([{^ip}], :ets.lookup(@ets, ip))
  end
end
