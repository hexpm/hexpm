defmodule HexWeb.API.ReleaseView do
  use HexWeb.Web, :view
  import Ecto

  def render("index." <> _, %{releases: releases}),
    do: render_many(releases, __MODULE__, "release")
  def render("show." <> _, %{release: release}),
    do: render_one(release, __MODULE__, "release")

  def render("release", %{release: release}) do
    package = release.package

    reqs = for {name, app, req, optional} <- release.requirements, into: %{} do
      {name, %{app: app, requirement: req, optional: optional}}
    end

    entity =
      release
      |> Map.take([:meta, :version, :has_docs, :inserted_at, :updated_at])
      |> Map.put(:url, release_url(HexWeb.Endpoint, :show, package, release))
      |> Map.put(:package_url, package_url(HexWeb.Endpoint, :show, package))
      |> Map.put(:requirements, reqs)
      |> if_value(release.has_docs, &Map.put(&1, :docs_url, HexWeb.Utils.docs_tarball_url(package, release)))
      |> if_value(assoc_loaded?(release.downloads), &load_downloads(&1, release))

    entity
  end

  defp load_downloads(entity, release) do
    downloads = if release.downloads, do: release.downloads.downloads, else: 0
    Map.put(entity, :downloads, downloads)
  end
end
