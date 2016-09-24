defmodule HexWeb do
  use Application

  def start(_type, _args) do
    import Supervisor.Spec, warn: false

    tmp_dir  = Application.get_env(:hex_web, :tmp_dir)
    ses_rate = Application.get_env(:hex_web, :ses_rate) |> String.to_integer

    HexWeb.BlockAddress.start

    children = [
      supervisor(HexWeb.Repo, []),
      supervisor(Task.Supervisor, [[name: HexWeb.Tasks]]),
      worker(HexWeb.RateLimit, [HexWeb.RateLimit]),
      worker(HexWeb.Throttle, [[name: HexWeb.SESThrottle, rate: ses_rate, unit: 1000]]),
      supervisor(HexWeb.Endpoint, []),
    ]

    File.mkdir_p(tmp_dir)
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
end
