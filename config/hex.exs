use Mix.Config

config :hex_web,
  user_confirm: false,
  docs_url:     System.get_env("HEX_DOCS_URL") || "http://localhost:4043",
  cdn_url:      System.get_env("HEX_CDN_URL")  || "http://localhost:4043",
  secret:       System.get_env("HEX_SECRET")   || "796f75666f756e64746865686578"

config :hex_web, HexWeb.Endpoint,
  http: [port: 4043],
  debug_errors: false

config :hex_web, HexWeb.Repo,
  adapter: Ecto.Adapters.Postgres,
  username: "postgres",
  password: "postgres",
  database: "hexweb_hex",
  hostname: "localhost",
  pool_size: 10

config :hex_web, HexWeb.Mailer,
  adapter: Bamboo.LocalAdapter

config :logger,
  level: :error
