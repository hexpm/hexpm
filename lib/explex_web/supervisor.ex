defmodule ExplexWeb.Supervisor do
  use Supervisor.Behaviour

  def start_link do
    :supervisor.start_link(__MODULE__, [])
  end

  def init([]) do
    tree = [ worker(ExplexWeb.Repo, []) ]
    supervise(tree, strategy: :one_for_all)
  end
end
