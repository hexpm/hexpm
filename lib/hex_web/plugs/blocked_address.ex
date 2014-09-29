defmodule HexWeb.Plugs.BlockedAddress do
  use Ecto.Model
  import Plug.Conn

  @ets :blocked_addresses

  schema "blocked_addresses" do
    field :ip, :string
    field :comment, :string
  end

  def start do
    :ets.new(@ets, [:named_table, :set, :public, read_concurrency: true])
    reload()
  end

  def reload do
    new_ips = HexWeb.Repo.all(HexWeb.Plugs.BlockedAddress)
              |> Enum.into(HashSet.new, & &1.ip)

    old_ips = :ets.tab2list(@ets) |> Enum.map(&elem(&1, 0))
    removed = Enum.filter(old_ips, &HashSet.member?(new_ips, &1))

    Enum.each(removed, &:ets.delete(@ets, &1))
    :ets.insert(@ets, Enum.map(new_ips, &{&1}))
  end

  def check(ip) do
    try do
      case :ets.lookup(@ets, ip) do
        [{^ip}] -> :ok
        [] -> :error
      end
    rescue ArgumentError ->
      start()
      case :ets.lookup(@ets, ip) do
        [{^ip}] -> :ok
        [] -> :error
      end
    end
  end

  def init(opts), do: opts

  def call(conn, _opts) do
    if conn.remote_ip do
      case check(ip(conn.remote_ip)) do
        :ok ->
          conn
          |> send_resp(401, "Blocked")
          |> halt
        :error ->
          conn
      end
    else
      conn
    end
  end

  defp ip({a, b, c, d}) do
    "#{a}.#{b}.#{c}.#{d}"
  end
end
