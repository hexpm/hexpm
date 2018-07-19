use Mix.Config

config :hexpm,
  tmp_dir: Path.expand("tmp/dev"),
  docs_url: "http://localhost:4002",
  cdn_url: "http://localhost:4000",
  secret: "796f75666f756e64746865686578",
  private_key: File.read!("test/fixtures/private.pem"),
  billing_key: "hex_billing_key",
  billing_url: "http://localhost:4001"

config :hexpm, Hexpm.Web.Endpoint,
  http: [port: 4000],
  debug_errors: true,
  code_reloader: true,
  cache_static_lookup: false,
  check_origin: false,
  pubsub: [name: Hexpm.PubSub, adapter: Phoenix.PubSub.PG2],
  watchers: [
    node: [
      "node_modules/brunch/bin/brunch",
      "watch",
      "--stdin",
      cd: Path.expand("../assets", __DIR__)
    ]
  ]

config :hexpm, Hexpm.Web.Endpoint,
  live_reload: [
    patterns: [
      ~r{priv/static/.*(js|css|png|jpeg|jpg|gif|svg)$},
      ~r{lib/hexpm/web/views/.*(ex)$},
      ~r{lib/hexpm/web/templates/.*(eex|md)$}
    ]
  ]

config :logger, :console, format: "[$level] $message\n"

config :phoenix, :stacktrace_depth, 20

config :hexpm, Hexpm.Repo,
  adapter: Ecto.Adapters.Postgres,
  username: "postgres",
  password: "postgres",
  database: "hexpm_dev",
  hostname: "localhost",
  pool_size: 5

config :hexpm, Hexpm.Emails.Mailer, adapter: Bamboo.LocalAdapter
