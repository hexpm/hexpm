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
      Plugins.Oban,
      Hexpm.PromEx.Plugins.Hexpm
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
