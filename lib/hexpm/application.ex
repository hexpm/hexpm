defmodule Hexpm.Application do
  use Application

  def start(_type, _args) do
    import Supervisor.Spec, warn: false

    tmp_dir  = Application.get_env(:hexpm, :tmp_dir)
    ses_rate = Application.get_env(:hexpm, :ses_rate) |> String.to_integer

    Hexpm.BlockAddress.start

    children = [
      supervisor(Hexpm.Repo, []),
      supervisor(Task.Supervisor, [[name: Hexpm.Tasks]]),
      worker(PlugAttack.Storage.Ets, [Hexpm.Web.Plugs.Attack, [clean_period: 60_000]]),
      worker(Hexpm.Throttle, [[name: Hexpm.SESThrottle, rate: ses_rate, unit: 1000]]),
      supervisor(Hexpm.Web.Endpoint, []),
    ]

    File.mkdir_p(tmp_dir)
    shutdown_on_eof()

    opts = [strategy: :one_for_one, name: Hexpm.Supervisor]
    Supervisor.start_link(children, opts)
  end

  def config_change(changed, _new, removed) do
    Hexpm.Web.Endpoint.config_change(changed, removed)
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
