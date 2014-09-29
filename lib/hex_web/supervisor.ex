defmodule HexWeb.Supervisor do
  use Supervisor

  def start_link do
    :supervisor.start_link(__MODULE__, [])
  end

  # Don't start RegistryBuilder during testing
  if Mix.env == :test do
    @tree [worker(HexWeb.Repo, [])]
  else
    @tree [worker(HexWeb.RegistryBuilder, []),
           worker(HexWeb.Repo, [])]
  end

  def init([]) do
    supervise(@tree, strategy: :one_for_one)
  end
end
