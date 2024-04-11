import Config

config :hexpm,
  billing_report: false,
  tmp_dir: Path.expand("../tmp/dev", __DIR__),
  private_key: Path.expand("../test/fixtures/private.pem", __DIR__) |> File.read!(),
  docs_url: "http://localhost:4002",
  diff_url: "http://localhost:4004",
  preview_url: "http://localhost:4005",
  cdn_url: "http://localhost:4000",
  billing_url: "http://localhost:4001",
  billing_key: "hex_billing_key"

config :hexpm, HexpmWeb.Endpoint,
  http: [port: 4000],
  debug_errors: true,
  code_reloader: true,
  cache_static_lookup: false,
  check_origin: false,
  pubsub_server: Hexpm.PubSub,
  watchers: [
    node: [
      "node_modules/webpack/bin/webpack.js",
      "--mode",
      "development",
      "--watch",
      "--watch-options-stdin",
      cd: Path.expand("../assets", __DIR__)
    ]
  ]

config :hexpm, HexpmWeb.Endpoint,
  live_reload: [
    patterns: [
      ~r{priv/static/.*(js|css|png|jpeg|jpg|gif|svg)$},
      ~r{lib/hexpm_web/views/.*(ex)$},
      ~r{lib/hexpm_web/templates/.*(eex|md)$}
    ]
  ]

config :logger, :default_formatter, format: "[$level] $message\n"

config :phoenix, :stacktrace_depth, 20

config :phoenix, :plug_init_mode, :runtime

config :hexpm, Hexpm.RepoBase,
  username: "postgres",
  password: "postgres",
  database: "hexpm_dev",
  hostname: "localhost",
  pool_size: 5

config :hexpm, Hexpm.Emails.Mailer, adapter: Bamboo.LocalAdapter
