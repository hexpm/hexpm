use Mix.Config

config :hexpm,
  secret: "${HEXPM_SECRET}",
  private_key: "${HEXPM_SIGNING_KEY}",
  s3_bucket: "${HEXPM_S3_BUCKET}",
  docs_bucket: "${HEXPM_DOCS_BUCKET}",
  logs_buckets: "${HEXPM_LOGS_BUCKETS}",
  docs_url: "${HEXPM_DOCS_URL}",
  cdn_url: "${HEXPM_CDN_URL}",
  email_host: "${HEXPM_EMAIL_HOST}",
  ses_rate: "${HEXPM_SES_RATE}",
  fastly_key: "${HEXPM_FASTLY_KEY}",
  fastly_hexrepo: "${HEXPM_FASTLY_HEXREPO}",
  billing_key: "${HEXPM_BILLING_KEY}",
  billing_url: "${HEXPM_BILLING_URL}",
  levenshtein_threshold: "${HEXPM_LEVENSHTEIN_THRESHOLD}",
  store_impl: Hexpm.Store.S3,
  billing_impl: Hexpm.Billing.Hexpm,
  cdn_impl: Hexpm.CDN.Fastly,
  tmp_dir: "tmp"

config :hexpm, HexpmWeb.Endpoint,
  http: [compress: true],
  url: [scheme: "https", port: 443],
  load_from_system_env: true,
  cache_static_manifest: "priv/static/cache_manifest.json"

config :hexpm, Hexpm.RepoBase, ssl: true

config :bcrypt_elixir, log_rounds: 12

config :rollbax,
  access_token: "${HEXPM_ROLLBAR_ACCESS_TOKEN}",
  environment: to_string(Mix.env()),
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

config :sasl, sasl_error_logger: false

config :logger, level: :info
