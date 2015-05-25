defmodule HexWeb.Supervisor do
  use Supervisor
  require Logger

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts)
  end

  def init(opts) do
    Logger.info "Starting Cowboy on port #{opts[:port]}"

    tree = [
      worker(HexWeb.Repo, []),
      worker(HexWeb.BlockedAddress, []),
      worker(HexWeb.API.RateLimit, [HexWeb.API.RateLimit]),
      worker(ConCache, [
        [
          ttl_check: :timer.seconds(1),
          ttl: :timer.seconds(15)
        ],
        [name: :hex_cache]
      ]),
      Plug.Adapters.Cowboy.child_spec(:http, HexWeb.Router, [], opts)
    ]
    supervise(tree, strategy: :rest_for_one)
  end
end
