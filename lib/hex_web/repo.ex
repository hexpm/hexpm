defmodule HexWeb.Repo do
  use Ecto.Repo, adapter: Ecto.Adapters.Postgres, env: Mix.env

  def url(:prod) do
    System.get_env("HEX_ECTO_URL")
  end

  def url(:dev),
    do: "ecto://postgres:postgres@localhost/hex_dev"

  def url(:test),
    do: "ecto://postgres:postgres@localhost/hex_test?size=1&max_overflow=0"

  def priv,
    do: :code.priv_dir(:hex_web)
end
