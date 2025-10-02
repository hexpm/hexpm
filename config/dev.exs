import Config

config :hexpm,
  billing_report: false,
  secret: "796f75666f756e64746865686578",
  jwt_signing_key: """
  -----BEGIN EC PRIVATE KEY-----
  MHcCAQEEIHUgIrJNc1hyxptBqaIXJhiJLC+sNx1e9PtWtybMMDjKoAoGCCqGSM49
  AwEHoUQDQgAENEaVGMojo1bTG/IR6W+grIx/hY97Mxp4OalFU3x/KxXX4ud/mtJL
  oCBc51fzxeYF1CYg2Ch+d3BgrKLFHHEJfw==
  -----END EC PRIVATE KEY-----
  """,
  tmp_dir: Path.expand("../tmp/dev", __DIR__),
  private_key: Path.expand("../test/fixtures/private.pem", __DIR__) |> File.read!(),
  docs_url: "http://localhost:4002",
  diff_url: "http://localhost:4004",
  preview_url: "http://localhost:4005",
  cdn_url: "http://localhost:4000",
  billing_url: "http://localhost:4001",
  billing_key: "hex_billing_key",
  dashboard_user: "hex_user",
  dashboard_password: "hex_password"

config :hexpm, HexpmWeb.Endpoint,
  http: [port: 4000],
  debug_errors: true,
  code_reloader: true,
  cache_static_lookup: false,
  check_origin: false,
  pubsub_server: Hexpm.PubSub,
  secret_key_base: "38K8orQfRHMC6ZWXIdgItQEiumeY+L2Ls0fvYfTMt4AoG5+DSFsLG6vMajNcd5Td",
  live_view: [signing_salt: "2UTSB72sZsF9KTlxefkIrFFPXTO7d+Ep"],
  watchers: [
    node: [
      "node_modules/webpack/bin/webpack.js",
      "--mode",
      "development",
      "--watch",
      "--watch-options-stdin",
      cd: Path.expand("../assets", __DIR__)
    ]
  ]

config :hexpm, HexpmWeb.Endpoint,
  live_reload: [
    patterns: [
      ~r{priv/static/.*(js|css|png|jpeg|jpg|gif|svg)$},
      ~r{lib/hexpm_web/views/.*(ex)$},
      ~r{lib/hexpm_web/templates/.*(eex|md)$}
    ]
  ]

config :phoenix_live_view,
  debug_heex_annotations: true,
  debug_attributes: true

config :logger, :default_formatter, format: "[$level] $message\n"

config :phoenix, :stacktrace_depth, 20

config :phoenix, :plug_init_mode, :runtime

config :hexpm, Hexpm.RepoBase,
  username: "postgres",
  password: "postgres",
  database: "hexpm_dev",
  hostname: "localhost",
  pool_size: 5

config :hexpm, Hexpm.Emails.Mailer, adapter: Bamboo.LocalAdapter
