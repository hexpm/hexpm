defmodule ExplexWeb.Supervisor do
  use Supervisor.Behaviour

  def start_link do
    :supervisor.start_link(__MODULE__, [])
  end

  if Mix.env == :test do
    def init([]) do
      tree = [ worker(ExplexWeb.Repo, []) ]
      supervise(tree, strategy: :one_for_one)
    end
  else
    def init([]) do
      tree = [ worker(ExplexWeb.RegistryBuilder, [[build_on_start: true]]),
               worker(ExplexWeb.Repo, []) ]
      supervise(tree, strategy: :one_for_one)
    end
  end
end
