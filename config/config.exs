use Mix.Config

store = if System.get_env("HEX_S3_BUCKET"), do: HexWeb.Store.S3, else: HexWeb.Store.Local
email = if System.get_env("HEX_SES_USERNAME"), do: HexWeb.Mail.SES, else: HexWeb.Mail.Local
cdn   = if System.get_env("HEX_FASTLY_KEY"), do: HexWeb.CDN.Fastly, else: HexWeb.CDN.Local

logs_buckets = if value = System.get_env("HEX_LOGS_BUCKETS"),
                 do: value |> String.split(";") |> Enum.map(&String.split(&1, ","))

config :hex_web,
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

  email_impl:   email,
  email_host:   System.get_env("HEX_EMAIL_HOST"),

  ses_rate:     System.get_env("HEX_SES_RATE") || "1000",

  cdn_impl:       cdn,
  fastly_key:     System.get_env("HEX_FASTLY_KEY"),
  fastly_hexdocs: System.get_env("HEX_FASTLY_HEXDOCS"),
  fastly_hexrepo: System.get_env("HEX_FASTLY_HEXREPO"),
  support_email:  "support@hex.pm",

  levenshtein_threshold: System.get_env("HEX_LEVENSHTEIN_THRESHOLD") || 2

config :hex_web, ecto_repos: [HexWeb.Repo]

config :ex_aws,
  access_key_id:     {:system, "HEX_S3_ACCESS_KEY"},
  secret_access_key: {:system, "HEX_S3_SECRET_KEY"}

config :ex_aws, :httpoison_opts,
  recv_timeout: 30_000,
  hackney: [pool: true]

config :comeonin,
  bcrypt_log_rounds: 4

config :porcelain,
  driver: Porcelain.Driver.Basic

config :hex_web, HexWeb.Endpoint,
  url: [host: "localhost"],
  root: Path.dirname(__DIR__),
  secret_key_base: "Cc2cUvbm9x/uPD01xnKmpmU93mgZuht5cTejKf/Z2x0MmfqE1ZgHJ1/hSZwd8u4L",
  render_errors: [accepts: ~w(html json elixir erlang)]

config :hex_web, HexWeb.Mailer,
  adapter: Bamboo.SMTPAdapter,
  server: System.get_env("HEX_SES_ENDPOINT") || "email-smtp.us-west-2.amazonaws.com",
  port: System.get_env("HEX_SES_PORT") || "587",
  username: System.get_env("HEX_SES_USERNAME"),
  password: System.get_env("HEX_SES_PASSWORD"),
  tls: :always,
  ssl: true,
  retries: 1

config :phoenix, :template_engines,
  md: HexWeb.MarkdownEngine

config :phoenix,
  stacktrace_depth: 20

config :phoenix, :generators,
  migration: true,
  binary_id: false

config :phoenix, :format_encoders,
  elixir: HexWeb.ElixirFormat,
  erlang: HexWeb.ErlangFormat,
  json: HexWeb.Jiffy

config :mime, :types, %{
  "application/vnd.hex+json"   => ["json"],
  "application/vnd.hex+elixir" => ["elixir"],
  "application/vnd.hex+erlang" => ["erlang"]
}

config :ecto,
  json_library: HexWeb.Jiffy

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

import_config "#{Mix.env}.exs"
