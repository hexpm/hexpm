use Mix.Config

config :hex_web,
  docs_url:    System.get_env("HEX_DOCS_URL") || "http://localhost:4000",
  cdn_url:     System.get_env("HEX_CDN_URL")  || "http://localhost:4000",
  secret:      System.get_env("HEX_SECRET")   || "796f75666f756e64746865686578",
  private_key: File.read!("test/fixtures/private.pem")

config :hex_web, HexWeb.Endpoint,
  http: [port: 4000],
  debug_errors: true,
  code_reloader: true,
  cache_static_lookup: false,
  check_origin: false,
  pubsub: [name: HexWeb.PubSub,
           adapter: Phoenix.PubSub.PG2],
  watchers: [node: ["node_modules/brunch/bin/brunch", "watch", "--stdin",
             cd: Path.expand("..", __DIR__)]]

config :hex_web, HexWeb.Endpoint,
  live_reload: [
    patterns: [
      ~r{priv/static/.*(js|css|png|jpeg|jpg|gif|svg)$},
      ~r{web/views/.*(ex)$},
      ~r{web/templates/.*(eex|md)$}
    ]
  ]

config :logger, :console, format: "[$level] $message\n"

config :phoenix, :stacktrace_depth, 20

config :hex_web, HexWeb.Repo,
  adapter: Ecto.Adapters.Postgres,
  username: "postgres",
  password: "postgres",
  database: "hexweb_dev",
  hostname: "localhost",
  pool_size: 5

config :hex_web, HexWeb.Mailer,
  adapter: Bamboo.LocalAdapter
