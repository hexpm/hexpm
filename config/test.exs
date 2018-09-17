use Mix.Config

config :hexpm,
  user_agent_req: false,
  tmp_dir: Path.expand("tmp/test"),
  private_key: File.read!("test/fixtures/private.pem"),
  public_key: File.read!("test/fixtures/public.pem"),
  cdn_url: "http://localhost:5000",
  docs_url: "http://localhost:5002",
  billing_impl: Hexpm.Billing.Mock

config :hexpm, Hexpm.Web.Endpoint,
  http: [port: 5000],
  server: false

config :hexpm, Hexpm.Emails.Mailer, adapter: Bamboo.TestAdapter

config :hexpm, Hexpm.Repo,
  adapter: Ecto.Adapters.Postgres,
  username: "postgres",
  password: "postgres",
  database: "hexpm_test",
  hostname: "localhost",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10,
  ownership_timeout: 61_000

config :logger, level: :error
