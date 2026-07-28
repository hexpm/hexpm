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
      # Queue lengths come from counting the jobs table, which every node does
      # on its own timer, so the default five seconds is a scan per node per
      # five seconds for a number that does not move that fast.
      {Plugins.Oban, poll_rate: :timer.minutes(1)},
      Hexpm.PromEx.Plugins.Hexpm,
      Hexpm.PromEx.Plugins.OutboundHttp
    ]
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
