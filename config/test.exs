import Config

config :hexpm,
  user_agent_req: false,
  tmp_dir: Path.expand("tmp/test"),
  private_key: File.read!("test/fixtures/private.pem"),
  public_key: File.read!("test/fixtures/public.pem"),
  cdn_url: "http://localhost:5000",
  docs_url: "http://localhost:5002",
  diff_url: "http://localhost:5004",
  preview_url: "http://localhost:5005",
  billing_impl: Hexpm.Billing.Mock,
  pwned_impl: Hexpm.Pwned.Mock

config :hexpm, HexpmWeb.Endpoint,
  http: [port: 5000],
  server: false

config :hexpm, Hexpm.Emails.Mailer, adapter: Bamboo.TestAdapter

config :hexpm, Hexpm.RepoBase,
  username: "postgres",
  password: "postgres",
  database: "hexpm_test",
  hostname: "localhost",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 20,
  ownership_timeout: 61_000

config :logger, level: :error
