import Config

config :hexpm,
  repo_bucket: {Hexpm.Store.Memory, "repo_bucket"},
  logs_bucket: {Hexpm.Store.Memory, "logs_bucket"},
  docs_bucket: {Hexpm.Store.Memory, "docs_bucket"},
  docs_private_bucket: {Hexpm.Store.Memory, "docs_private_bucket"},
  preview_bucket: {Hexpm.Store.Memory, "preview_bucket"},
  secret: "796f75666f756e64746865686578",
  jwt_signing_key: """
  -----BEGIN EC PRIVATE KEY-----
  MHcCAQEEIHUgIrJNc1hyxptBqaIXJhiJLC+sNx1e9PtWtybMMDjKoAoGCCqGSM49
  AwEHoUQDQgAENEaVGMojo1bTG/IR6W+grIx/hY97Mxp4OalFU3x/KxXX4ud/mtJL
  oCBc51fzxeYF1CYg2Ch+d3BgrKLFHHEJfw==
  -----END EC PRIVATE KEY-----
  """,
  user_agent_req: false,
  tmp_dir: Path.expand("tmp/test"),
  private_key: File.read!("test/fixtures/private.pem"),
  public_key: File.read!("test/fixtures/public.pem"),
  cdn_url: "http://localhost:5000",
  docs_url: "http://localhost:5002",
  private_docs_url: "http://localhost:5002",
  diff_url: "http://localhost:5004",
  img_url: "http://localhost:5000/img",
  img_proxy_secret: "test_img_proxy_secret_key_for_hmac",
  readme_host: "readme.localhost",
  readme_url: "http://readme.localhost:5000",
  fastly_hexrepo: "fastly_hexrepo",
  fastly_hexdocs: "fastly_hexdocs",
  fastly_hexdocs_private: "fastly_hexdocs_private",
  fastly_key: "fastly_key",
  fastly_docs_key: "fastly_docs_key",
  fastly_purge_wait: 200,
  billing_impl: Hexpm.Billing.Mock,
  pwned_impl: Hexpm.Pwned.Mock,
  http_impl: Hexpm.HTTP.Mock,
  cache_enabled: false,
  skip_advisory_locks: true

config :hexpm, HexpmWeb.Endpoint,
  http: [port: 5000],
  server: false,
  secret_key_base: "38K8orQfRHMC6ZWXIdgItQEiumeY+L2Ls0fvYfTMt4AoG5+DSFsLG6vMajNcd5Td",
  live_view: [signing_salt: "2UTSB72sZsF9KTlxefkIrFFPXTO7d+Ep"]

config :hexpm, Hexpm.Emails.Mailer, adapter: Swoosh.Adapters.Test
config :swoosh, :api_client, false

config :hexpm, Oban, testing: :manual, queues: false, plugins: false

config :hexpm, Hexpm.RepoBase,
  username: "postgres",
  password: "postgres",
  database: "hexpm_test",
  hostname: "localhost",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 20,
  ownership_timeout: 61_000

config :logger, level: :error

config :hexpm, :hcaptcha,
  sitekey: "sitekey",
  secret: "secret"

# Don't sleep waiting for Sentry to flush in tests.
config :hexpm, sentry_flush_ms: 0
