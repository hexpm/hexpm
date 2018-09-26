defmodule Hexpm.Web.API.PackageDownloadView do
  use Hexpm.Web, :view

  def render("index." <> _, %{package_download: packages}) do
    render_many(packages, __MODULE__, "show")
  end

  def render("show." <> _, %{package_download: package}) do
    render_one(package, __MODULE__, "show")
  end

  def render("show", %{package_download: package}) do
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
  end
end
