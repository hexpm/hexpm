defmodule HexWeb.API.ReleaseView do
  use HexWeb.Web, :view
  import Ecto

  def render("index." <> _, %{releases: releases}),
    do: render_many(releases, __MODULE__, "release")
  def render("show." <> _, %{release: release}),
    do: render_one(release, __MODULE__, "release")

  def render("release", %{release: release}) do
    package = release.package

    reqs = Enum.into(release.requirements, %{}, fn req ->
      {req.name, Map.take(req, ~w(app requirement optional)a)}
    end)

    meta =
      release.meta
      |> Map.take([:app, :build_tools, :elixir])
      |> Map.update!(:build_tools, &Enum.uniq/1)

    entity =
      release
      |> Map.take([:version, :has_docs, :inserted_at, :updated_at])
      |> Map.put(:meta, meta)
      |> Map.put(:url, api_release_url(Endpoint, :show, package, release))
      |> Map.put(:package_url, api_package_url(Endpoint, :show, package))
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
