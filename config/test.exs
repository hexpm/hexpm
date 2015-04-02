use Mix.Config

config :hex_web, HexWeb.Repo,
  url: System.get_env("TEST_DATABASE_URL") ||
       "ecto://postgres:postgres@localhost/hexweb_test",
  size: "1",
  max_overflow: "0"

config :logger,
  level: :warn
