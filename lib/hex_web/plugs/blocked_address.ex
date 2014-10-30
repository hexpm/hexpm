defmodule HexWeb.BlockedAddress do
  use Ecto.Model
  use GenServer
  import Plug.Conn

  @ets :blocked_addresses

  schema "blocked_addresses" do
    field :ip, :string
    field :comment, :string
  end

  def start_link do
    GenServer.start_link(__MODULE__, [])
  end

  def init([]) do
    :ets.new(@ets, [:named_table, :set, :public, read_concurrency: true])
    reload()
    {:ok, :ok}
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
    @ets :blocked_addresses

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
