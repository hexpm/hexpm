defmodule HexWeb.Supervisor do
  use Supervisor

  def start_link do
    :supervisor.start_link(__MODULE__, [])
  end

  # Don't start RegistryBuilder during testing
  if Mix.env == :test do
    def init([]) do
      tree = [ worker(HexWeb.Repo, []) ]
      supervise(tree, strategy: :one_for_one)
    end
  else
    def init([]) do
      tree = [ worker(HexWeb.RegistryBuilder, []),
               worker(HexWeb.Repo, []) ]
      supervise(tree, strategy: :one_for_one)
    end
  end
end
