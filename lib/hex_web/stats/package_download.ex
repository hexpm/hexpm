defmodule HexWeb.Stats.PackageDownload do
  use Ecto.Model

  queryable "package_downloads", primary_key: false do
    belongs_to :package, HexWeb.Package
    field :view, :binary
    field :downloads, :integer
  end

  def refresh do
    Ecto.Adapters.Postgres.query(
       HexWeb.Repo,
       "REFRESH MATERIALIZED VIEW package_downloads",
       [])
  end
end
