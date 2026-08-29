defmodule Hexpm.PromEx do
  use PromEx, otp_app: :hexpm

  alias PromEx.Plugins

  @impl true
  def plugins do
    [
      Plugins.Application,
      Plugins.Beam,
      {Plugins.Phoenix, router: HexpmWeb.Router, endpoint: HexpmWeb.Endpoint},
      {Plugins.Ecto, repos: [Hexpm.RepoBase]},
      Hexpm.PromEx.Plugins.Hexpm,
      Hexpm.PromEx.Plugins.EctoLatency,
      Hexpm.PromEx.Plugins.OutboundHttp
    ] ++ oban_plugins()
  end

  # Queue lengths are counted from the jobs table and zero-filled from the
  # node's own queue config, so a node that runs no queues never reports a
  # zero and its gauges keep the last count they saw. Only nodes that run the
  # queues report Oban metrics. The count is a scan of the table per node, so
  # it runs once a minute rather than the default five seconds.
  defp oban_plugins do
    case Application.fetch_env!(:hexpm, Oban)[:queues] do
      queues when queues in [false, []] -> []
      _queues -> [{Plugins.Oban, poll_rate: :timer.minutes(1)}]
    end
  end

  @impl true
  def dashboard_assigns do
    [
      datasource_id: "prometheus",
      default_selected_interval: "5m"
    ]
  end

  @impl true
  def dashboards do
    [
      {:prom_ex, "application.json"},
      {:prom_ex, "beam.json"},
      {:prom_ex, "phoenix.json"},
      {:prom_ex, "ecto.json"},
      {:prom_ex, "oban.json"}
    ]
  end
end
