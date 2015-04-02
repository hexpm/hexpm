defmodule HexWeb.Stats.ReleaseDownload do
  use Ecto.Model
  alias HexWeb.Stats.ReleaseDownload

  @primary_key false

  schema "release_downloads" do
    belongs_to :release, HexWeb.Release, references: :id
    field :downloads, :integer
  end

  def refresh do
    Ecto.Adapters.Postgres.query(
       HexWeb.Repo,
       "REFRESH MATERIALIZED VIEW release_downloads",
       [])
  end

  def release(release) do
    from(rd in ReleaseDownload,
         where: rd.release_id == ^release.id,
         select: rd.downloads)
    |> HexWeb.Repo.one
  end
end
