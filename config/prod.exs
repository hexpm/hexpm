import Config

config :hexpm,
  billing_impl: Hexpm.Billing.Hexpm,
  cdn_impl: Hexpm.CDN.Fastly,
  hexdocs_search_impl: Hexpm.Hexdocs.Search.Typesense,
  hexdocs_queue_producer: BroadwaySQS.Producer,
  hexdocs_gcs_put_debounce: 3000,
  preview_queue_producer: BroadwaySQS.Producer,
  pwned_impl: Hexpm.Pwned.HaveIBeenPwned,
  tmp_dir: "tmp"

config :hexpm, :features, package_reports: false

config :hexpm, HexpmWeb.Endpoint,
  url: [scheme: "https", port: 443],
  cache_static_manifest: "priv/static/cache_manifest.json"

config :bcrypt_elixir, log_rounds: 12

config :sentry,
  enable_source_code_context: true,
  root_source_code_paths: [File.cwd!()],
  before_send: {Hexpm.Application, :sentry_before_send}

config :hexpm,
  topologies: [
    kubernetes: [
      strategy: Cluster.Strategy.Kubernetes,
      config: [
        mode: :dns,
        kubernetes_node_basename: "hexpm",
        kubernetes_selector: "app=hexpm",
        polling_interval: 10_000
      ]
    ]
  ]

config :phoenix, :serve_endpoints, true

config :logger, level: :info

config :logger, :default_formatter, metadata: [:request_id]

config :hexpm, Oban,
  peer: Oban.Peers.Database,
  plugins: [
    {Oban.Plugins.Cron,
     crontab: [
       {"* * * * *", Hexpm.Billing.Report},
       {"*/30 * * * *", Hexpm.Security.Updater}
     ],
     timezone: "Etc/UTC"},
    {Oban.Plugins.Pruner, max_age: 30 * 24 * 60 * 60},
    {Oban.Plugins.Lifeline, interval: 60_000, rescue_after: 360_000}
  ]
