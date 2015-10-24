use Mix.Config

config :hex_web,
  port: "4042"

config :hex_web, HexWeb.Repo,
  url: System.get_env("TEST_DATABASE_URL") ||
       "ecto://postgres:postgres@localhost/hexweb_test",
  size: 1,
  max_overflow: 0

config :hex_web,
  url:      System.get_env("HEX_URL")      || "http://localhost:4042",
  docs_url: System.get_env("HEX_DOCS_URL") || "http://localhost:4042",
  cdn_url:  System.get_env("HEX_CDN_URL")  || "http://localhost:4042",
  secret:   System.get_env("HEX_SECRET")   || "796f75666f756e64746865686578",
  redis_url: System.get_env("REDIS_URL")    || "redis://localhost:6379"

config :logger,
  level: :warn
