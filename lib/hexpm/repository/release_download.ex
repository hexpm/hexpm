defmodule Hexpm.Repository.ReleaseDownload do
  use Hexpm.Schema

  @derive HexpmWeb.Stale
  @primary_key false

  schema "release_downloads" do
    belongs_to(:package, Package, references: :id)
    belongs_to(:release, Release, references: :id)
    field :downloads, :integer
  end

  def release(release) do
    from(rd in ReleaseDownload, where: rd.release_id == ^release.id)
  end

  def by_period(release_id, :all, false) do
    from(d in ReleaseDownload,
      where: d.release_id == ^release_id,
      select: %Download{
        package_id: d.package_id,
        release_id: d.release_id,
        downloads: d.downloads
      }
    )
  end

  def by_period(release_id, :all, true) do
    from(d in Download,
      where: d.release_id == ^release_id,
      group_by: [d.package_id, d.release_id],
      select: %Download{
        package_id: d.package_id,
        release_id: d.release_id,
        downloads: sum(d.downloads)
      }
    )
  end

  def by_period(release_id, filter, _date_filtered?) do
    from(d in Download, where: d.release_id == ^release_id)
    |> Download.query_filter(filter)
  end
end
