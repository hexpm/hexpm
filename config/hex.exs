use Mix.Config

config :hex_web,
    user_confirm: false,
    store: HexWeb.Store.Local,
    email: HexWeb.Email.Local,
    url: "http://localhost:4043",
    secret: "796f75666f756e64746865686578",
    port: "4043"

config :hex_web, HexWeb.Repo,
  url: System.get_env("TEST_DATABASE_URL") ||
       "ecto://postgres:postgres@localhost/hex_test",
  size: 1,
  max_overflow: 0

config :hex_web,
  url:      System.get_env("HEX_URL")      || "http://localhost:4043",
  docs_url: System.get_env("HEX_DOCS_URL") || "http://localhost:4043",
  cdn_url:  System.get_env("HEX_CDN_URL")  || "http://localhost:4043",
  secret:   System.get_env("HEX_SECRET")   || "796f75666f756e64746865686578"

config :logger,
  level: :warn
