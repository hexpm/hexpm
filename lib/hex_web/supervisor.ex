defmodule HexWeb.Supervisor do
  use Supervisor

  def start_link do
    Supervisor.start_link(__MODULE__, [])
  end

  def init([]) do
    tree = [
      worker(HexWeb.Repo, []),
      worker(HexWeb.BlockedAddress, []),
      worker(HexWeb.API.RateLimit, [HexWeb.API.RateLimit])
    ]
    supervise(tree, strategy: :one_for_one)
  end
end
