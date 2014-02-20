defmodule ExplexWeb.Supervisor do
  use Supervisor.Behaviour

  def start_link do
    :supervisor.start_link(__MODULE__, [])
  end

  # Don't start RegistryBuilder during testing
  if Mix.env == :test do
    def init([]) do
      tree = [ worker(ExplexWeb.Repo, []) ]
      supervise(tree, strategy: :one_for_one)
    end
  else
    def init([]) do
      tree = [ worker(ExplexWeb.RegistryBuilder, []),
               worker(ExplexWeb.Repo, []) ]
      supervise(tree, strategy: :one_for_one)
    end
  end
end
