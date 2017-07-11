defmodule Hexpm.Web.API.PackageView do
  use Hexpm.Web, :view
  alias Hexpm.Web.API.{DownloadView, ReleaseView, UserView}

  def render("index." <> _, %{packages: packages}) do
    render_many(packages, __MODULE__, "show")
  end
  def render("show." <> _, %{package: package}) do
    render_one(package, __MODULE__, "show")
  end

  def render("show", %{package: package}) do
    %{
      name: package.name,
      inserted_at: package.inserted_at,
      updated_at: package.updated_at,
      url: api_package_url(Endpoint, :show, package),
      meta: %{
        description: package.meta.description,
        licenses: package.meta.licenses,
        links: package.meta.links,
        maintainers: package.meta.maintainers,
      }
    }
    |> include_if_loaded(:releases, package.releases, ReleaseView, "minimal.json", package: package)
    |> include_if_loaded(:downloads, package.downloads, DownloadView, "show.json")
    |> include_if_loaded(:owners, package.owners, UserView, "minimal.json")
    |> group_downloads()
  end

  defp group_downloads(%{downloads: downloads} = package) do
    Map.put(package, :downloads, Enum.reduce(downloads, %{}, &Map.merge(&1, &2)))
  end
  defp group_downloads(package) do
    package
  end
end
