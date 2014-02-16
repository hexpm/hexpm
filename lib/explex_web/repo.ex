defmodule ExplexWeb.Repo do
  use Ecto.Repo, adapter: Ecto.Adapters.Postgres, env: Mix.env

  def url(:dev) do
    # Special case for integration testing explex client
    System.get_env("EXPLEX_ALT_ECTO_URL") ||
    "ecto://explex:explex@localhost/explex_dev"
  end

  def url(:test),
    do: "ecto://explex:explex@localhost/explex_test?size=1&max_overflow=0"

  def priv,
    do: :code.priv_dir(:explex_web)
end
