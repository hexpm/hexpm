use Mix.Config

if Mix.env == :test do
  log_level = :warn
else
  log_level = :debug
end

if Mix.env == :prod do
  work_factor = 12
else
  work_factor = 4
end

config :hex_web,
  password_work_factor: work_factor,

  url:      System.get_env("HEX_URL") || "http://localhost:4000",
  app_host: System.get_env("APP_HOST"),

  s3_url:        System.get_env("S3_URL") || "http://s3.amazonaws.com",
  s3_bucket:     System.get_env("S3_BUCKET"),
  s3_access_key: System.get_env("S3_ACCESS_KEY"),
  s3_secret_key: System.get_env("S3_SECRET_KEY"),
  cdn_url:       System.get_env("CDN_URL") || "http://localhost:4000"

config :logger,
  level: log_level

config :logger, :console,
  format: "$date $time [$level] $message\n"
