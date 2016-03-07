use Mix.Config

config :hex_web,
  docs_url: System.get_env("HEX_DOCS_URL") || "http://localhost:4042",
  cdn_url:  System.get_env("HEX_CDN_URL")  || "http://localhost:4042",
  secret:   System.get_env("HEX_SECRET")   || "796f75666f756e64746865686578"

config :hex_web, HexWeb.Endpoint,
  http: [port: 4001],
  server: false

config :hex_web, HexWeb.Repo,
  adapter: Ecto.Adapters.Postgres,
  username: "postgres",
  password: "postgres",
  database: "hexweb_test",
  hostname: "localhost",
  pool: Ecto.Adapters.SQL.Sandbox

config :logger,
  level: :error
