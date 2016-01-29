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
      |> Map.put(:url, api_url(["packages", package.name, "releases", to_string(release.version)]))
      |> Map.put(:package_url, api_url(["packages", package.name]))
      |> Map.put(:requirements, reqs)
      |> Enum.into(%{})

    if release.has_docs do
      entity = Map.put(entity, :docs_url, Release.docs_url(release))
    end

    if assoc_loaded?(release.downloads) do
      entity = Map.put(entity, :downloads, release.downloads)
    end

    entity
  end
end
