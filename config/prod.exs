use Mix.Config

config :hex_web,
  password_work_factor: 12

config :hex_web, :database,
  url: System.get_env("DATABASE_URL")
  lazy: false,
  size: "20",
  max_overflow: "0"

config :logger,
  level: :info
