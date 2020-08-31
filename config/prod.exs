import Config

config :hexpm,
  billing_impl: Hexpm.Billing.Hexpm,
  cdn_impl: Hexpm.CDN.Fastly,
  pwned_impl: Hexpm.Pwned.HaveIBeenPwned,
  tmp_dir: "tmp"

config :hexpm, :features, package_reports: false

config :hexpm, HexpmWeb.Endpoint,
  http: [compress: true],
  url: [scheme: "https", port: 443],
  load_from_system_env: true,
  cache_static_manifest: "priv/static/cache_manifest.json"

config :hexpm, Hexpm.RepoBase, ssl: true

config :bcrypt_elixir, log_rounds: 12

config :rollbax,
  environment: "prod",
  enabled: true,
  enable_crash_reports: true

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

config :logger,
  level: :info,
  metadata: [:request_id]
