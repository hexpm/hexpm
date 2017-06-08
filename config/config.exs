use Mix.Config

store = if System.get_env("HEX_S3_BUCKET"), do: Hexpm.Store.S3, else: Hexpm.Store.Local
cdn   = if System.get_env("HEX_FASTLY_KEY"), do: Hexpm.CDN.Fastly, else: Hexpm.CDN.Local

logs_buckets = if value = System.get_env("HEX_LOGS_BUCKETS"),
                 do: value |> String.split(";") |> Enum.map(&String.split(&1, ","))

smtp_port = String.to_integer(System.get_env("HEX_SES_PORT") || "587")

config :hexpm,
  user_confirm:   true,
  user_agent_req: true,
  tmp_dir:        Path.expand("tmp"),
  app_host:       System.get_env("APP_HOST"),

  auth_gate:        System.get_env("HEX_AUTH_GATE"),
  secret:           System.get_env("HEX_SECRET"),
  private_key:      System.get_env("HEX_SIGNING_KEY"),
  cookie_sign_salt: "lYEJ7Wc8jFwNrPke",
  cookie_encr_salt: "TZDiyTeFQ819hsC3",

  store_impl:   store,
  s3_url:       System.get_env("HEX_S3_URL") || "https://s3.amazonaws.com",
  s3_bucket:    System.get_env("HEX_S3_BUCKET"),
  docs_bucket:  System.get_env("HEX_DOCS_BUCKET"),
  logs_buckets: logs_buckets,
  docs_url:     System.get_env("HEX_DOCS_URL"),
  cdn_url:      System.get_env("HEX_CDN_URL"),

  email_host:   System.get_env("HEX_EMAIL_HOST"),
  ses_rate:     System.get_env("HEX_SES_RATE") || "1000",

  cdn_impl:       cdn,
  fastly_key:     System.get_env("HEX_FASTLY_KEY"),
  fastly_hexdocs: System.get_env("HEX_FASTLY_HEXDOCS"),
  fastly_hexrepo: System.get_env("HEX_FASTLY_HEXREPO"),
  support_email:  "support@hex.pm",

  levenshtein_threshold: System.get_env("HEX_LEVENSHTEIN_THRESHOLD") || 2

config :hexpm, ecto_repos: [Hexpm.Repo]

config :ex_aws,
  access_key_id:     {:system, "HEX_S3_ACCESS_KEY"},
  secret_access_key: {:system, "HEX_S3_SECRET_KEY"}

config :comeonin,
  bcrypt_log_rounds: 4

config :porcelain,
  driver: Porcelain.Driver.Basic

config :hexpm, Hexpm.Web.Endpoint,
  url: [host: "localhost"],
  root: Path.dirname(__DIR__),
  secret_key_base: "Cc2cUvbm9x/uPD01xnKmpmU93mgZuht5cTejKf/Z2x0MmfqE1ZgHJ1/hSZwd8u4L",
  render_errors: [view: Hexpm.Web.ErrorView, accepts: ~w(html json elixir erlang)]

config :hexpm, Hexpm.Repo,
  pool: DBConnection.Sojourn,
  protector: false,
  overload_alarm: false

config :sasl,
  sasl_error_logger: false

config :hexpm, Hexpm.Emails.Mailer,
  adapter: Bamboo.SMTPAdapter,
  server: System.get_env("HEX_SES_ENDPOINT") || "email-smtp.us-west-2.amazonaws.com",
  port: smtp_port,
  username: System.get_env("HEX_SES_USERNAME"),
  password: System.get_env("HEX_SES_PASSWORD"),
  tls: :always,
  ssl: false,
  retries: 1

config :phoenix, :template_engines,
  md: Hexpm.Web.MarkdownEngine

config :phoenix,
  stacktrace_depth: 20

config :phoenix, :generators,
  migration: true,
  binary_id: false

config :phoenix, :format_encoders,
  elixir: Hexpm.Web.ElixirFormat,
  erlang: Hexpm.Web.ErlangFormat,
  json: Hexpm.Web.Jiffy

config :mime, :types, %{
  "application/vnd.hex+json"   => ["json"],
  "application/vnd.hex+elixir" => ["elixir"],
  "application/vnd.hex+erlang" => ["erlang"]
}

config :ecto,
  json_library: Hexpm.Web.Jiffy

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

import_config "#{Mix.env}.exs"
