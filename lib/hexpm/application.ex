defmodule Hexpm.Application do
  use Application

  def start(_type, _args) do
    topologies = cluster_topologies()
    read_only_mode()
    Hexpm.BlockAddress.start()

    children = [
      Hexpm.RepoBase,
      {Task.Supervisor, name: Hexpm.Tasks},
      {Cluster.Supervisor, [topologies, [name: Hexpm.ClusterSupervisor]]},
      {Phoenix.PubSub, name: Hexpm.PubSub, adapter: Phoenix.PubSub.PG2},
      HexpmWeb.RateLimitPubSub,
      {PlugAttack.Storage.Ets, name: HexpmWeb.Plugs.Attack.Storage, clean_period: 60_000},
      {Hexpm.Billing.Report, name: Hexpm.Billing.Report, interval: 60_000},
      goth_spec(),
      HexpmWeb.Telemetry,
      HexpmWeb.Endpoint
    ]

    File.mkdir_p(Application.get_env(:hexpm, :tmp_dir))
    shutdown_on_eof()

    opts = [strategy: :one_for_one, name: Hexpm.Supervisor]
    Supervisor.start_link(children, opts)
  end

  def config_change(changed, _new, removed) do
    HexpmWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  # Make sure we exit after hex client tests are finished running
  if Mix.env() == :hex do
    def shutdown_on_eof() do
      spawn_link(fn ->
        IO.gets(:stdio, '') == :eof && System.halt(0)
      end)
    end
  else
    def shutdown_on_eof(), do: nil
  end

  defp read_only_mode() do
    mode = System.get_env("HEXPM_READ_ONLY_MODE") == "1"
    Application.put_env(:hexpm, :read_only_mode, mode)
  end

  defp cluster_topologies() do
    if System.get_env("HEXPM_CLUSTER") == "1" do
      Application.get_env(:hexpm, :topologies) || []
    else
      []
    end
  end

  if Mix.env() == :prod do
    defp goth_spec() do
      credentials =
        "HEXPM_GCP_CREDENTIALS"
        |> System.fetch_env!()
        |> Jason.decode!()

      options = [scope: "https://www.googleapis.com/auth/devstorage.read_write"]
      {Goth, name: Hexpm.Goth, source: {:service_account, credentials, options}}
    end
  else
    defp goth_spec() do
      {Task, fn -> :ok end}
    end
  end
end
