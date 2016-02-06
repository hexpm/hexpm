defmodule HexWeb.ReleaseDownload do
  use HexWeb.Web, :model

  @primary_key false

  schema "release_downloads" do
    belongs_to :release, Release, references: :id
    field :downloads, :integer
  end

  # TODO: Figure out a place to move this
  def refresh do
    Ecto.Adapters.SQL.query(
       HexWeb.Repo,
       "REFRESH MATERIALIZED VIEW release_downloads",
       [])
  end

  def release(release) do
    from(rd in ReleaseDownload,
         where: rd.release_id == ^release.id)
  end
end
