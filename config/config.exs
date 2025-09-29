import Config

config :hexpm,
  user_confirm: true,
  user_agent_req: true,
  billing_report: true,
  secret: "796f75666f756e64746865686578",
  jwt_signing_key: """
  -----BEGIN PRIVATE KEY-----
  MIIEvgIBADANBgkqhkiG9w0BAQEFAASCBKgwggSkAgEAAoIBAQC+HQY9Dh6OVrRT
  TP5OJLGH8TcHqIeyvoSm1UMV0kZd7/PKC2AYlcNILRgtpeLfFSy/b9hl4mrhQ7PA
  65QYWFEfNJeIxqUPmqAOEHlKRk2gRSAdHUMAeBUfuyOPDgsz0Ww8akxCHjtQZ5BT
  hpxOtP4RBV9Z7qX4fXe+8uWkg6FqJL7Zi11l50/bAIxadCASabc3q7QjSWcnRVDL
  UPZl86klKc0jm79ez8RBEDwH61Wxg6uhI4xWANJ2klGZR7RLglqUPrWtXwToru0I
  Uz//DJV3kv9CGynJK3sx3ZnxvEiLo69cIMfECTUMgOLqpNzBXVsvVkq/YM86cXWj
  1BjqsDiZAgMBAAECggEALVPLPHxk0agfh2roiSYbg9+BsNxAOmBNTV+0hnvjlhsT
  Y51RtJrkfA1wYdXW4TxxtlUK4cPZmsrjDUC9xw4rjUajSJOgIDfMKH5KBOj9MhS5
  IufqpS58Ttv2DvIYvqqUZVUsyGjf2HxQv3FtTCDAILvIr68EOFpl1gugsBhIQH+H
  eBfcDuqodTMM5XgjuqFiuYQ3bC9fuOqRNXWusy+cjQ5SbmdFbVurdVJnuguwA/lp
  RdYXsJNlNCHhd6kZ0PJ7eDI/NGbxkqkPzrKoqBABmOHc3fkvVZOPa28U4pBzbdV1
  GSuHnSznna32olyBO8N6/l15gIsQJAj8zBrO1qVktwKBgQD3BxvNTeh/F33MEotN
  f2hORlvVMNLDZrRpB5jhDeAzOXHzdRX3Hh3Euf5dlomqygfA6sDLULIbZHFxS5xC
  UYXHn2FR/Jd03IIiE5S8rW1axIv2tWgfOnZLhsjTVPgk2+zrQmJ3tl/uQtoNTSVE
  Afj1+Kd28Fm+xSeavW4bWlimkwKBgQDFBLgwNo4hymAS6zgoAnf2kCBNbkKj2IOR
  L4QUYSwD/MJRz1PCENqdpQmT/S7guKcwk2J5nFAFbrn4TfSOjoOqVTIzOczhKRK+
  XG+OINiA2NU/hNOGTkX1d1FKibTpO9GvZ/jvsuNmeutrMOgOYGfMhasNm/va39gy
  jNHs/iHTowKBgCqiaHL7okflFwoUnURH3Am+bPUTkxy0aijCbelRysMsg/U/3QWk
  hgDBFRyz8Zive70ZByNQDx1ZLZcfNJ3hkhRM9q/+x2kc8bzN4lraF8iVqY5v6sOR
  BH+uiJSo0pcR+gb0kygUKuRlV1r6WJcvO/e/7a9CdkrNnjM/xHQmGKzPAoGBALq/
  Bndsvrx4vygvnUMPU/Z6FqROZww3Jj5v85n9oWMGKoqxIotIvm+/B50m11Batt7s
  VONArvj3Q3+BJNYbb+H8b2Du4Kxr6kBWDceCirVW0osqs/USLG3Hc15buQd6k/7X
  ZraNsc5ppMwtx0gZSUorST/VIp0MoDkKEdG58QZRAoGBANQqp0XlreXNahiqYEEf
  Y/rUlCy07vtPyhfIEHj2hT5wTS3OmjvGQ2cPa9xq8Y8NopJEJyXrz09ENKZusSul
  B9o7GX516N7oB7rCGO6AHuFS2MPur04Jzie0VI0ooW1WNLEiHN0rcUWZwqKpyWe6
  jVMP6EYMBd+pttmfsCFsY4vF
  -----END PRIVATE KEY-----
  """,
  support_email: "support@hex.pm",
  repo_bucket: {Hexpm.Store.Local, "repo_bucket"},
  logs_bucket: {Hexpm.Store.Local, "logs_bucket"},
  cdn_impl: Hexpm.CDN.Local,
  billing_impl: Hexpm.Billing.Local,
  pwned_impl: Hexpm.Pwned.Local,
  dashboard_user: "hex_user",
  dashboard_password: "hex_password"

config :hexpm, :features, package_reports: true

config :hexpm, ecto_repos: [Hexpm.RepoBase]

config :ex_aws,
  json_codec: Jason

config :bcrypt_elixir, log_rounds: 4

config :hexpm, HexpmWeb.Endpoint,
  url: [host: "localhost"],
  root: Path.dirname(__DIR__),
  render_errors: [view: HexpmWeb.ErrorView, accepts: ~w(html json elixir erlang)],
  secret_key_base: "38K8orQfRHMC6ZWXIdgItQEiumeY+L2Ls0fvYfTMt4AoG5+DSFsLG6vMajNcd5Td",
  live_view: [signing_salt: "2UTSB72sZsF9KTlxefkIrFFPXTO7d+Ep"],
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

import_config "#{Mix.env()}.exs"
