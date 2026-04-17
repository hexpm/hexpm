import Config

config :hexpm,
  user_confirm: true,
  user_agent_req: true,
  billing_report: true,
  cache_enabled: true,
  support_email: "support@hex.pm",
  repo_bucket: {Hexpm.Store.Local, "repo_bucket"},
  logs_bucket: {Hexpm.Store.Local, "logs_bucket"},
  cdn_impl: Hexpm.CDN.Local,
  billing_impl: Hexpm.Billing.Local,
  pwned_impl: Hexpm.Pwned.Local,
  sudo_timeout: Duration.new!(hour: 1)

config :hexpm, :features, package_reports: true

config :hexpm, ecto_repos: [Hexpm.RepoBase]

config :ex_aws,
  json_codec: Jason

config :bcrypt_elixir, log_rounds: 4

config :hexpm, HexpmWeb.Endpoint,
  url: [host: "localhost"],
  root: Path.dirname(__DIR__),
  render_errors: [view: HexpmWeb.ErrorView, accepts: ~w(html json elixir erlang)],
  pubsub_server: Hexpm.PubSub

config :hexpm, Hexpm.RepoBase,
  priv: "priv/repo",
  migration_timestamps: [type: :utc_datetime_usec]

config :hexpm, Hexpm.Emails.Mailer,
  adapter: Bamboo.SendGridAdapter,
  hackney_opts: [
    recv_timeout: :timer.minutes(1)
  ]

config :phoenix, :template_engines, md: HexpmWeb.MarkdownEngine

config :phoenix, stacktrace_depth: 20

config :phoenix, :generators,
  migration: true,
  binary_id: false

config :phoenix, :format_encoders,
  elixir: HexpmWeb.ElixirFormat,
  erlang: HexpmWeb.ErlangFormat,
  json: Jason

config :phoenix, :json_library, Jason

config :mime,
  types: %{
    "application/vnd.hex+json" => ["json"],
    "application/vnd.hex+elixir" => ["elixir"],
    "application/vnd.hex+erlang" => ["erlang"]
  },
  extensions: %{
    "json" => "application/json"
  }

config :logger, :default_formatter, format: "[$level] $metadata$message\n"

config :esbuild,
  version: "0.25.0",
  hexpm: [
    args:
      ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

config :tailwind,
  version: "4.1.11",
  default: [
    args: ~w(
      --input=./assets/css/tailwind.css
      --output=./priv/static/assets/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

config :ueberauth, Ueberauth,
  providers: [
    github: {Ueberauth.Strategy.Github, [default_scope: "user:email"]}
  ]

import_config "#{Mix.env()}.exs"
