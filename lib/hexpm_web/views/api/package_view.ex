defmodule HexpmWeb.API.PackageView do
  use HexpmWeb, :view
  alias HexpmWeb.API.{DownloadView, ReleaseView, RetirementView, UserView}

  def render("index." <> _, %{packages: packages}) do
    render_many(packages, __MODULE__, "show")
  end

  def render("show." <> _, %{package: package}) do
    render_one(package, __MODULE__, "show")
  end

  def render("show", %{package: package}) do
    %{
      repository: package.organization.name,
      name: package.name,
      inserted_at: package.inserted_at,
      updated_at: package.updated_at,
      url: url_for_package(package),
      html_url: html_url_for_package(package),
      docs_html_url: docs_html_url_for_package(package),
      meta: %{
        description: package.meta.description,
        licenses: package.meta.licenses || [],
        links: package.meta.links || %{},
        maintainers: package.meta.maintainers || []
      }
    }
    |> include_if_loaded(
      :releases,
      package.releases,
      ReleaseView,
      "minimal.json",
      package: package
    )
    |> include_if_loaded(:retirements, package.releases, RetirementView, "package.json")
    |> include_if_loaded(:downloads, package.downloads, DownloadView, "show.json")
    |> include_if_loaded(:owners, package.owners, UserView, "minimal.json")
    |> group_downloads()
    |> group_retirements()
  end

  defp group_downloads(%{downloads: downloads} = package) do
    Map.put(package, :downloads, Enum.reduce(downloads, %{}, &Map.merge(&1, &2)))
  end

  defp group_downloads(package), do: package

  defp group_retirements(%{retirements: retirements} = package) do
    Map.put(package, :retirements, Enum.reduce(retirements, %{}, &Map.merge(&1, &2)))
  end

  defp group_retirements(package), do: package
end
