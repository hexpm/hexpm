import Config

config :hexpm,
  user_confirm: true,
  user_agent_req: true,
  billing_report: true,
  cache_enabled: true,
  support_email: "support@hex.pm",
  repo_bucket: {Hexpm.Store.Local, "repo_bucket"},
  logs_bucket: {Hexpm.Store.Local, "logs_bucket"},
  docs_bucket: {Hexpm.Store.Local, "docs_bucket"},
  docs_private_bucket: {Hexpm.Store.Local, "docs_private_bucket"},
  preview_bucket: {Hexpm.Store.Local, "preview_bucket"},
  cdn_impl: Hexpm.CDN.Local,
  hexdocs_search_impl: Hexpm.Hexdocs.Search.Local,
  hexdocs_source_repo_impl: Hexpm.Hexdocs.SourceRepo.GitHub,
  hexdocs_queue_id: "test",
  hexdocs_queue_producer: Broadway.DummyProducer,
  hexdocs_queue_concurrency: 1,
  hexdocs_gcs_put_debounce: 0,
  preview_queue_id: "test",
  preview_queue_producer: Broadway.DummyProducer,
  preview_queue_concurrency: 1,
  hexdocs_special_packages: %{
    "eex" => "elixir-lang/elixir",
    "elixir" => "elixir-lang/elixir",
    "ex_unit" => "elixir-lang/elixir",
    "iex" => "elixir-lang/elixir",
    "logger" => "elixir-lang/elixir",
    "mix" => "elixir-lang/elixir",
    "hex" => "hexpm/hex"
  },
  billing_impl: Hexpm.Billing.Local,
  pwned_impl: Hexpm.Pwned.Local,
  sudo_timeout: Duration.new!(hour: 1),
  sudo_force_timeout: Duration.new!(second: 30)

config :hexpm, :features, package_reports: true

config :hexpm, ecto_repos: [Hexpm.RepoBase]

config :hexpm, Oban,
  repo: Hexpm.RepoBase,
  queues: [periodic: 2, heavy: 1],
  shutdown_grace_period: 300_000

config :ex_aws,
  json_codec: Jason,
  http_client: ExAws.Request.Req

config :sentry, client: Hexpm.SentryClient

config :bcrypt_elixir, log_rounds: 4

config :hexpm, HexpmWeb.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  url: [host: "localhost"],
  root: Path.dirname(__DIR__),
  render_errors: [
    view: HexpmWeb.ErrorView,
    accepts: ~w(html json elixir erlang),
    root_layout: {HexpmWeb.LayoutView, :root},
    layout: {HexpmWeb.LayoutView, :app}
  ],
  pubsub_server: Hexpm.PubSub

config :hexpm, Hexpm.RepoBase,
  priv: "priv/repo",
  migration_timestamps: [type: :utc_datetime_usec]

config :swoosh, :api_client, Swoosh.ApiClient.Finch
config :swoosh, :finch_name, Hexpm.Finch

config :hexpm, Hexpm.Emails.Mailer, adapter: Swoosh.Adapters.Sendgrid

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

config :mdex_native, syntax_highlighter: :lumis

import_config "#{Mix.env()}.exs"
