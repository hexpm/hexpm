defmodule HexWeb.Stats.PackageDownload do
  use Ecto.Model
  import Ecto.Query, only: [from: 2]
  alias HexWeb.Stats.PackageDownload

  schema "package_downloads", primary_key: false do
    belongs_to :package, HexWeb.Package, references: :id
    field :view, :string
    field :downloads, :integer
  end

  def refresh do
    Ecto.Adapters.Postgres.query(
       HexWeb.Repo,
       "REFRESH MATERIALIZED VIEW package_downloads",
       [])
  end

  def top(view, count) do
    view = "#{view}"
    from(pd in PackageDownload,
         join: p in assoc(pd, :package),
         where: not is_nil(pd.package_id) and pd.view == ^view,
         order_by: [desc: pd.downloads],
         limit: ^count,
         select: {p.name, pd.downloads})
    |> HexWeb.Repo.all
  end

  def total do
    from(pd in PackageDownload, where: is_nil(pd.package_id))
    |> HexWeb.Repo.all
    |> Enum.map(&{:"#{&1.view}", &1.downloads || 0})
  end

  def package(package) do
    from(pd in PackageDownload, where: pd.package_id == ^package.id)
    |> HexWeb.Repo.all
    |> Enum.map(&{:"#{&1.view}", &1.downloads || 0})
  end
end
