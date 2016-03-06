defmodule HexWeb.API.PackageView do
  use HexWeb.Web, :view
  import Ecto

  def render("index." <> _, %{packages: packages}),
    do: render_many(packages, __MODULE__, "package")
  def render("show." <> _, %{package: package}),
    do: render_one(package, __MODULE__, "package")

  def render("package", %{package: package}) do
    package
    |> Map.take([:name, :inserted_at, :updated_at])
    |> Map.put(:meta, Map.take(package.meta, [:contributors, :description, :licenses, :links, :maintainers]))
    |> Map.put(:url, package_url(HexWeb.Endpoint, :show, package))
    |> if_value(assoc_loaded?(package.releases), &load_releases(&1, package, package.releases))
    |> if_value(assoc_loaded?(package.downloads), &load_downloads(&1, package.downloads))
  end

  defp load_releases(entity, package, releases) do
    releases =
      Enum.map(releases, fn release ->
        release
        |> Map.take([:version, :inserted_at, :updated_at])
        |> Map.put(:url, release_url(HexWeb.Endpoint, :show, package, release))
      end)

    Map.put(entity, :releases, releases)
  end

  defp load_downloads(entity, downloads) do
    downloads =
      Enum.into(downloads, %{}, fn download ->
        {download.view, download.downloads}
      end)

    Map.put(entity, :downloads, downloads)
  end
end
