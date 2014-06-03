defmodule HexWeb.Repo do
  use Ecto.Repo, adapter: Ecto.Adapters.Postgres, env: Mix.env

  def conf(:prod),
    do: parse_url(System.get_env("DATABASE_URL")) ++ [lazy: false]

  def conf(:dev),
    do: parse_url "ecto://postgres:postgres@localhost/hex_dev"

  def conf(:test),
    do: parse_url "ecto://postgres:postgres@localhost/hex_test?size=1&max_overflow=0"

  def priv,
    do: :code.priv_dir(:hex_web)

  # def log(action, fun) do
  #   IO.inspect action
  #   fun.()
  # end
end
