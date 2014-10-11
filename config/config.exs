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

  url:      System.get_env("HEX_URL"),
  app_host: System.get_env("APP_HOST"),

  s3_url:        System.get_env("HEX_S3_URL") || "http://s3.amazonaws.com",
  s3_bucket:     System.get_env("HEX_S3_BUCKET"),
  s3_access_key: System.get_env("HEX_S3_ACCESS_KEY"),
  s3_secret_key: System.get_env("HEX_S3_SECRET_KEY"),
  docs_bucket:   System.get_env("HEX_DOCS_BUCKET"),
  logs_bucket:   System.get_env("HEX_LOGS_BUCKET"),
  docs_url:      System.get_env("HEX_DOCS_URL"),
  cdn_url:       System.get_env("HEX_CDN_URL"),

  ses_endpoint:    System.get_env("HEX_SES_ENDPOINT") || "email-smtp.us-west-2.amazonaws.com",
  ses_port:        System.get_env("HEX_SES_PORT") || "587",
  ses_user:        System.get_env("HEX_SES_USERNAME"),
  ses_pass:        System.get_env("HEX_SES_PASSWORD"),
  ses_source_addr: System.get_env("HEX_SES_SOURCE_ADDRESS"),

  secret: System.get_env("HEX_SECRET")

if Mix.env in [:dev, :test] do
  config :hex_web,
    url:      System.get_env("HEX_URL")      || "http://localhost:4000",
    docs_url: System.get_env("HEX_DOCS_URL") || "http://localhost:4000",
    cdn_url:  System.get_env("HEX_CDN_URL")  || "http://localhost:4000",
    secret:   System.get_env("HEX_SECRET")   || "796f75666f756e64746865686578"
end


config :logger,
  level: log_level

config :logger, :console,
  format: "$date $time [$level] $message\n"
