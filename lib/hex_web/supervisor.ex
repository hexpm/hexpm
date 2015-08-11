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
      supervisor(Task.Supervisor, [[name: HexWeb.PublishTasks]]),
      worker(HexWeb.BlockedAddress, []),
      worker(HexWeb.API.RateLimit, [HexWeb.API.RateLimit]),
      Plug.Adapters.Cowboy.child_spec(:http, HexWeb.Router, [], opts)
    ]
    supervise(tree, strategy: :rest_for_one)
  end
end
