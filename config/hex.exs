use Mix.Config

config :hexpm,
  tmp_dir: Path.expand("tmp/hex"),
  private_key: File.read!("test/fixtures/private.pem"),
  user_confirm: false,
  docs_url: "http://localhost:4043",
  cdn_url: "http://localhost:4043"

config :hexpm, HexpmWeb.Endpoint,
  http: [port: 4043, protocol_options: [max_keepalive: :infinity]],
  debug_errors: false

config :hexpm, HexWeb.Repo,
  username: "postgres",
  password: "postgres",
  database: "hexpm_hex",
  hostname: "localhost",
  pool_size: 10

config :hexpm, Hexpm.RepoBase,
  username: "postgres",
  password: "postgres",
  database: "hexpm_hex",
  hostname: "localhost",
  pool_size: 10

config :hexpm, Hexpm.Emails.Mailer, adapter: Bamboo.LocalAdapter

config :logger, level: :error
