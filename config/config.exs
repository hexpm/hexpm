use Mix.Config

config :hexpm,
  user_confirm: true,
  user_agent_req: true,
  secret: "796f75666f756e64746865686578",
  support_email: "support@hex.pm",
  store_impl: Hexpm.Store.Local,
  cdn_impl: Hexpm.CDN.Local,
  billing_impl: Hexpm.Billing.Local

config :hexpm, ecto_repos: [Hexpm.Repo]

config :ex_aws,
  access_key_id: {:system, "HEXPM_S3_ACCESS_KEY"},
  secret_access_key: {:system, "HEXPM_S3_SECRET_KEY"},
  json_codec: Jason

config :bcrypt_elixir, log_rounds: 4

config :hexpm, Hexpm.Web.Endpoint,
  url: [host: "localhost"],
  root: Path.dirname(__DIR__),
  render_errors: [view: Hexpm.Web.ErrorView, accepts: ~w(html json elixir erlang)]

config :hexpm, Hexpm.Repo,
  pool: DBConnection.Sojourn,
  protector: false,
  overload_alarm: false,
  underload_alarm: false

config :sasl, sasl_error_logger: false

config :hexpm, Hexpm.Emails.Mailer, adapter: Hexpm.Emails.Bamboo.SESAdapter

config :phoenix, :template_engines, md: Hexpm.Web.MarkdownEngine

config :phoenix, stacktrace_depth: 20

config :phoenix, :generators,
  migration: true,
  binary_id: false

config :phoenix, :format_encoders,
  elixir: Hexpm.Web.ElixirFormat,
  erlang: Hexpm.Web.ErlangFormat,
  json: Jason

config :mime, :types, %{
  "application/vnd.hex+json" => ["json"],
  "application/vnd.hex+elixir" => ["elixir"],
  "application/vnd.hex+erlang" => ["erlang"]
}

config :ecto, json_library: Jason

config :rollbax, enabled: false

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

import_config "#{Mix.env()}.exs"
