use Mix.Config

pool_size = String.to_integer(System.get_env("HEX_POOL_SIZE") || "20")

config :hexpm,
  cookie_sign_salt: System.get_env("HEX_COOKIE_SIGNING_SALT"),
  cookie_encr_salt: System.get_env("HEX_COOKIE_ENCRYPTION_SALT")

config :hexpm, Hexpm.Web.Endpoint,
  http: [compress: true],
  url: [scheme: "https", port: 443],
  force_ssl: [hsts: true, host: nil, rewrite_on: [:x_forwarded_proto]],
  load_from_system_env: true,
  cache_static_manifest: "priv/static/cache_manifest.json"

config :hexpm, Hexpm.Repo,
  adapter: Ecto.Adapters.Postgres,
  pool_size: pool_size,
  queue_size: pool_size * 5,
  ssl: true

config :bcrypt_elixir, log_rounds: 12

config :rollbax,
  access_token: System.get_env("ROLLBAR_ACCESS_TOKEN"),
  environment: to_string(Mix.env()),
  enabled: !!System.get_env("ROLLBAR_ACCESS_TOKEN"),
  enable_crash_reports: true

# Don't include date time on heroku
config :logger, :console, format: "[$level] $message\n"

config :logger, level: :warn
