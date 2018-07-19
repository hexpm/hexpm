use Mix.Config

config :hexpm,
  tmp_dir: Path.expand("tmp/hex"),
  user_confirm: false,
  docs_url: "http://localhost:4043",
  cdn_url: "http://localhost:4043",
  secret: "796f75666f756e64746865686578"

config :hexpm, Hexpm.Web.Endpoint,
  http: [port: 4043, protocol_options: [max_keepalive: :infinity]],
  debug_errors: false

config :hexpm, HexWeb.Repo,
  adapter: Ecto.Adapters.Postgres,
  username: "postgres",
  password: "postgres",
  database: "hexpm_hex",
  hostname: "localhost",
  pool_size: 10

config :hexpm, Hexpm.Repo,
  adapter: Ecto.Adapters.Postgres,
  username: "postgres",
  password: "postgres",
  database: "hexpm_hex",
  hostname: "localhost",
  pool_size: 10

config :hexpm, Hexpm.Emails.Mailer, adapter: Bamboo.LocalAdapter

config :logger, level: :error
