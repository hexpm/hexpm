defmodule Hexpm.Repository.PackageDownload do
  use Hexpm.Web, :schema
  import Hexpm.QueryAPI, only: [coalesce: 2]

  @derive Hexpm.Web.Stale
  @primary_key false

  schema "package_downloads" do
    belongs_to :package, Package, references: :id
    field :view, :string
    field :downloads, :integer
  end

  def top(repository, view, count) do
    from(pd in PackageDownload,
      join: p in assoc(pd, :package),
      where: not is_nil(pd.package_id),
      where: p.repository_id == ^repository.id,
      where: pd.view == ^view,
      order_by: [desc: pd.downloads],
      limit: ^count,
      select: {p.name, p.inserted_at, p.meta, pd.downloads}
    )
  end

  def total() do
    from(pd in PackageDownload,
      where: is_nil(pd.package_id),
      select: {pd.view, coalesce(pd.downloads, 0)}
    )
  end

  def package(package) do
    from(pd in PackageDownload,
      where: pd.package_id == ^package.id,
      select: {pd.view, coalesce(pd.downloads, 0)}
    )
  end

  def packages_and_all_download_views(packages) do
    package_ids = Enum.map(packages, &(&1.id))

    from(pd in PackageDownload,
      join: p in assoc(pd, :package),
      where: pd.package_id in ^package_ids,
      select: {p.id, pd.view, coalesce(pd.downloads, 0)})
  end

  def packages(packages, view) do
    package_ids = Enum.map(packages, &(&1.id))

    from(pd in PackageDownload,
      join: p in assoc(pd, :package),
      where: pd.package_id in ^package_ids,
      where: pd.view == ^view,
      select: {p.id, pd.downloads}
    )
  end
end
