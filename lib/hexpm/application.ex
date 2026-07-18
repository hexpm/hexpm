defmodule Hexpm.Application do
  use Application

  @environment Mix.env()

  def start(_type, _args) do
    :logger.add_handler(:sentry_handler, Sentry.LoggerHandler, %{})

    read_only_mode()
    setup_tmp_dir()

    mode = mode()
    if web_mode?(mode), do: Hexpm.BlockAddress.start()
    children = children(mode)

    shutdown_on_eof()

    opts = [strategy: :one_for_one, name: Hexpm.Supervisor]
    Supervisor.start_link(children, opts)
  end

  def config_change(changed, _new, removed) do
    if Process.whereis(HexpmWeb.Endpoint) do
      HexpmWeb.Endpoint.config_change(changed, removed)
    end

    :ok
  end

  def mode(value \\ System.get_env("HEXPM_MODE")), do: mode(@environment, value)

  def mode(:prod, value) when value in [nil, "", "web"], do: :web
  def mode(:prod, "worker"), do: :worker

  def mode(:prod, value) do
    raise ArgumentError,
          "invalid HEXPM_MODE #{inspect(value)}; expected \"web\" or \"worker\""
  end

  def mode(environment, _value) when environment in [:dev, :test, :hex], do: :all

  def children(mode) when mode in [:web, :worker, :all] do
    common_children() ++
      if(mode in [:worker, :all], do: worker_before_oban_children(), else: []) ++
      [oban_child()] ++
      if(mode in [:worker, :all], do: worker_after_oban_children(), else: []) ++
      if(mode in [:web, :all], do: web_children(), else: [])
  end

  defp web_mode?(mode), do: mode in [:web, :all]

  def sentry_before_send(%Sentry.Event{original_exception: exception} = event) do
    cond do
      websocket_protocol_error?(event) -> nil
      Plug.Exception.status(exception) < 500 -> nil
      Sentry.DefaultEventFilter.exclude_exception?(exception, event.source) -> nil
      true -> event
    end
  end

  # Bandit stops the websocket connection process with a non-shutdown reason when a
  # client sends invalid frames, which gets logged as a crash even though the client
  # was correctly rejected
  defp websocket_protocol_error?(%Sentry.Event{extra: %{crash_reason: "{:deserializing," <> _}}),
    do: true

  defp websocket_protocol_error?(%Sentry.Event{}), do: false

  # Make sure we exit after hex client tests are finished running
  if Mix.env() == :hex do
    def shutdown_on_eof() do
      spawn_link(fn ->
        IO.gets(:stdio, ~c"") == :eof && System.halt(0)
      end)
    end
  else
    def shutdown_on_eof(), do: nil
  end

  defp read_only_mode() do
    read_only? = System.get_env("HEXPM_READ_ONLY_MODE") == "1"
    Hexpm.OAuth.ReadOnly.configure!(read_only?)
  end

  defp setup_tmp_dir() do
    if dir = Application.get_env(:hexpm, :tmp_dir) do
      File.mkdir_p!(dir)
      Application.put_env(:hexpm, :tmp_dir, Path.expand(dir))
    end
  end

  defp setup() do
    fun = fn ->
      if System.get_env("HEXPM_SETUP") == "1" do
        Hexpm.setup()
      end
    end

    %{
      id: :task_setup,
      start: {Task, :start_link, [fun]},
      restart: :temporary
    }
  end

  defp load_caches() do
    fun = fn ->
      Hexpm.OAuth.Clients.load_cache()
    end

    %{
      id: :load_caches,
      start: {Task, :start_link, [fun]},
      restart: :temporary
    }
  end

  defp cluster_topologies() do
    if System.get_env("HEXPM_CLUSTER") == "1" do
      Application.get_env(:hexpm, :topologies) || []
    else
      []
    end
  end

  defp common_children do
    [
      Hexpm.RepoBase,
      {Finch, name: Hexpm.Finch, pools: finch_pools()},
      Hexpm.TmpDir,
      {Task.Supervisor, name: Hexpm.Tasks},
      goth_spec(),
      setup(),
      HexpmWeb.Telemetry
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp oban_child, do: {Oban, Application.fetch_env!(:hexpm, Oban)}

  defp finch_pools() do
    gcs_url = Application.get_env(:hexpm, :gcs_url, "https://storage.googleapis.com")
    %{gcs_url => [size: 50, count: 2]}
  end

  defp web_children do
    [
      {Cluster.Supervisor, [cluster_topologies(), [name: Hexpm.ClusterSupervisor]]},
      {Phoenix.PubSub, name: Hexpm.PubSub, adapter: Phoenix.PubSub.PG2},
      HexpmWeb.RateLimitPubSub,
      {PlugAttack.Storage.Ets, name: HexpmWeb.Plugs.Attack.Storage, clean_period: 60_000},
      {Hexpm.Cache,
       name: Hexpm.Cache,
       interval: 3_600_000,
       enabled: Application.fetch_env!(:hexpm, :cache_enabled)},
      load_caches(),
      HexpmWeb.Endpoint
    ]
  end

  defp worker_before_oban_children,
    do: [{Hexpm.Hexdocs.Debouncer, name: Hexpm.Hexdocs.Debouncer}]

  defp worker_after_oban_children, do: [Hexpm.Hexdocs.Queue, Hexpm.Preview.Queue]

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
    defp goth_spec, do: nil
  end
end
