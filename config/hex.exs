import Config

config :hexpm,
  secret: "796f75666f756e64746865686578",
  jwt_signing_key: """
  -----BEGIN EC PRIVATE KEY-----
  MHcCAQEEIHUgIrJNc1hyxptBqaIXJhiJLC+sNx1e9PtWtybMMDjKoAoGCCqGSM49
  AwEHoUQDQgAENEaVGMojo1bTG/IR6W+grIx/hY97Mxp4OalFU3x/KxXX4ud/mtJL
  oCBc51fzxeYF1CYg2Ch+d3BgrKLFHHEJfw==
  -----END EC PRIVATE KEY-----
  """,
  tmp_dir: Path.expand("tmp/hex"),
  private_key: File.read!("test/fixtures/private.pem"),
  user_confirm: false,
  docs_url: "http://localhost:4043",
  diff_url: "http://localhost:4004",
  preview_url: "http://localhost:4005",
  cdn_url: "http://localhost:4043"

config :hexpm, HexpmWeb.Endpoint,
  http: [port: 4043, protocol_options: [max_keepalive: :infinity]],
  debug_errors: false,
  secret_key_base: "38K8orQfRHMC6ZWXIdgItQEiumeY+L2Ls0fvYfTMt4AoG5+DSFsLG6vMajNcd5Td",
  live_view: [signing_salt: "2UTSB72sZsF9KTlxefkIrFFPXTO7d+Ep"]

config :hexpm, Hexpm.RepoBase,
  username: "postgres",
  password: "postgres",
  database: "hexpm_hex",
  hostname: "localhost",
  pool_size: 10

config :hexpm, Hexpm.Emails.Mailer, adapter: Bamboo.LocalAdapter

config :logger, level: :error
