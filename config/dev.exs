use Mix.Config

config :hex_web, HexWeb.Repo,
  url: System.get_env("DEV_DATABASE_URL") ||
       "ecto://postgres:postgres@localhost/hexweb_dev"

config :hex_web,
  url:       System.get_env("HEX_URL")      || "http://localhost:4000",
  docs_url:  System.get_env("HEX_DOCS_URL") || "http://localhost:4000",
  cdn_url:   System.get_env("HEX_CDN_URL")  || "http://localhost:4000",
  secret:    System.get_env("HEX_SECRET")   || "796f75666f756e64746865686578",
  redis_url: System.get_env("REDIS_URL")    || "redis://localhost:6379"
