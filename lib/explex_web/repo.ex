defmodule ExplexWeb.Repo do
  use Ecto.Repo, adapter: Ecto.Adapters.Postgres

  def url do
    "ecto://explex:explex@localhost/explex_dev"
  end
end
