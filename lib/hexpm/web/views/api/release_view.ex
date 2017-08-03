defmodule Hexpm.Web.API.ReleaseView do
  use Hexpm.Web, :view
  alias Hexpm.Web.API.RetirementView

  def render("index." <> _, %{releases: releases}) do
    render_many(releases, __MODULE__, "show")
  end
  def render("show." <> _, %{release: release}) do
    render_one(release, __MODULE__, "show")
  end
  def render("minimal." <> _, %{release: release, package: package}) do
    render_one(release, __MODULE__, "minimal", %{package: package})
  end

  def render("show", %{release: release}) do
    %{
      version: release.version,
      has_docs: release.has_docs,
      inserted_at: release.inserted_at,
      updated_at: release.updated_at,
      retirement: render_one(release.retirement, RetirementView, "show.json"),
      package_url: package_url(release.package),
      url: release_url(release.package, release),
      html_url: html_url(release.package, release),
      requirements: requirements(release.requirements),
      meta: %{
        app: release.meta.app,
        build_tools: Enum.uniq(release.meta.build_tools),
        elixir: release.meta.elixir,
      },
    }
    |> include_if_loaded(:downloads, release.downloads, &downloads/1)
  end

  def render("minimal", %{release: release, package: package}) do
    %{
      version: release.version,
      url: release_url(package, release),
    }
  end

  defp requirements(requirements) do
    Enum.into(requirements, %{}, fn req ->
      {req.name, Map.take(req, ~w(app requirement optional)a)}
    end)
  end

  defp downloads(%Ecto.Association.NotLoaded{}), do: 0
  defp downloads(nil), do: 0
  defp downloads(downloads), do: downloads.downloads

  defp html_url(%Package{repository_id: 1} = package, release) do
    package_url(Endpoint, :show, package, to_string(release.version), [])
  end
  defp html_url(%Package{} = package, release) do
    package_url(Endpoint, :show, package.repository, package, to_string(release.version), [])
  end

  defp package_url(%Package{repository_id: 1} = package) do
    api_package_url(Endpoint, :show, package, [])
  end
  defp package_url(%Package{} = package) do
    api_package_url(Endpoint, :show, package.repository, package, [])
  end

  defp release_url(%Package{repository_id: 1} = package, release) do
    api_release_url(Endpoint, :show, package, to_string(release.version), [])
  end
  defp release_url(%Package{} = package, release) do
    api_release_url(Endpoint, :show, package.repository, package, to_string(release.version), [])
  end
end
