use Mix.Config

config :hex_web, HexWeb.Repo,
  url: System.get_env("DATABASE_URL"),
  lazy: false,
  pool_size: System.get_env("NUM_DATABASE_CONNS") || 20

config :comeonin,
  bcrypt_log_rounds: 12

config :logger,
  level: :info

# Don't include date time on heroku
config :logger, :console,
  format: "[$level] $message\n"
