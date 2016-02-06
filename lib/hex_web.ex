defmodule HexWeb do
  use Application

  def start(_type, _args) do
    import Supervisor.Spec, warn: false

    HexWeb.BlockAddress.start

    children = [
      supervisor(HexWeb.Repo, []),
      supervisor(Task.Supervisor, [[name: HexWeb.PublishTasks]]),
      worker(HexWeb.RateLimit, [HexWeb.RateLimit]),
      supervisor(HexWeb.Endpoint, []),
    ]

    File.mkdir_p(Application.get_env(:hex_web, :tmp_dir))
    shutdown_on_eof()

    opts = [strategy: :one_for_one, name: HexWeb.Supervisor]
    Supervisor.start_link(children, opts)
  end

  def config_change(changed, _new, removed) do
    HexWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  # Make sure we exit after hex client tests are finished running
  if Mix.env == :hex do
    def shutdown_on_eof do
      spawn_link(fn ->
        IO.gets(:stdio, '') == :eof && System.halt(0)
      end)
    end
  else
    def shutdown_on_eof, do: nil
  end

  defprotocol Render do
    @moduledoc """
    Render entities to something that can be showed publicly.
    Used, for example, when converting entities to JSON responses.
    """

    @spec render(term) :: map
    def render(entity)
  end
end
