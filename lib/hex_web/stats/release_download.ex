defmodule HexWeb.Stats.ReleaseDownload do
  use Ecto.Model

  queryable "release_downloads", primary_key: false do
    belongs_to :release, HexWeb.Release
    field :downloads, :integer
  end

  def refresh do
    Ecto.Adapters.Postgres.query(
       HexWeb.Repo,
       "REFRESH MATERIALIZED VIEW release_downloads",
       [])
  end
end
