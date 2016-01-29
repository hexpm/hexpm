defmodule HexWeb.API.PackageView do
  use HexWeb.Web, :view
  import Ecto

  def render("index." <> _, %{packages: packages}),
    do: render_many(packages, __MODULE__, "package")
  def render("show." <> _, %{package: package}),
    do: render_one(package, __MODULE__, "package")

  def render("package", %{package: package}) do
    entity =
      package
      |> Map.take([:name, :meta, :inserted_at, :updated_at])
      |> Map.put(:url, api_url(["packages", package.name]))

    if assoc_loaded?(package.releases) do
      releases =
        Enum.map(package.releases, fn release ->
          release
          |> Map.take([:version, :inserted_at, :updated_at])
          |> Map.put(:url, api_url(["packages", package.name, "releases", to_string(release.version)]))
        end)
      entity = Map.put(entity, :releases, releases)
    end

    if assoc_loaded?(package.downloads) do
      downloads =
        Enum.into(package.downloads, %{}, fn download ->
          {download.view, download.downloads}
        end)
      entity = Map.put(entity, :downloads, downloads)
    end

    entity
  end
end
