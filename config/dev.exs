use Mix.Config

config :hexpm,
  tmp_dir: Path.expand("tmp/dev"),
  private_key: File.read!("test/fixtures/private.pem"),
  docs_url: "http://localhost:4002",
  cdn_url: "http://localhost:4000",
  billing_url: "http://localhost:4001",
  billing_key: "hex_billing_key"

config :hexpm, HexpmWeb.Endpoint,
  http: [port: 4000],
  debug_errors: true,
  code_reloader: true,
  cache_static_lookup: false,
  check_origin: false,
  pubsub: [name: Hexpm.PubSub],
  watchers: [
    node: [
      "node_modules/brunch/bin/brunch",
      "watch",
      "--stdin",
      cd: Path.expand("../assets", __DIR__)
    ]
  ]

config :hexpm, HexpmWeb.Endpoint,
  live_reload: [
    patterns: [
      ~r{priv/static/.*(js|css|png|jpeg|jpg|gif|svg)$},
      ~r{lib/hexpm/web/views/.*(ex)$},
      ~r{lib/hexpm/web/templates/.*(eex|md)$}
    ]
  ]

config :logger, :console, format: "[$level] $message\n"

config :phoenix, :stacktrace_depth, 20

config :hexpm, Hexpm.RepoBase,
  username: "postgres",
  password: "postgres",
  database: "hexpm_dev",
  hostname: "localhost",
  pool_size: 5

config :hexpm, Hexpm.Emails.Mailer, adapter: Bamboo.LocalAdapter
