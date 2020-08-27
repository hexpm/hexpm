defmodule HexpmWeb.API.PackageView do
  use HexpmWeb, :view
  alias HexpmWeb.API.{DownloadView, ReleaseView, RetirementView, UserView}
  alias HexpmWeb.PackageView

  def render("index." <> _, %{packages: packages}) do
    render_many(packages, __MODULE__, "show")
  end

  def render("show." <> _, %{package: package}) do
    render_one(package, __MODULE__, "show")
  end

  def render("audit_logs." <> _, %{audit_logs: audit_logs}) do
    render_many(audit_logs, HexpmWeb.API.AuditLogView, "show")
  end

  def render("show", %{package: package}) do
    latest_release = Release.latest_version(package.releases, only_stable: false)
    latest_stable_release = Release.latest_version(package.releases, only_stable: true)
    release = latest_stable_release || latest_release

    %{
      repository: package.repository.name,
      name: package.name,
      inserted_at: package.inserted_at,
      updated_at: package.updated_at,
      url: ViewHelpers.url_for_package(package),
      html_url: ViewHelpers.html_url_for_package(package),
      docs_html_url: ViewHelpers.docs_html_url_for_package(package),
      latest_version: latest_release.version,
      latest_stable_version: latest_stable_release && latest_stable_release.version,
      configs: %{
        "mix.exs": PackageView.dep_snippet(:mix, package, release),
        "rebar.config": PackageView.dep_snippet(:rebar, package, release),
        "erlang.mk": PackageView.dep_snippet(:erlang_mk, package, release)
      },
      meta: %{
        description: package.meta.description,
        licenses: package.meta.licenses || [],
        links: package.meta.links || %{},
        maintainers: package.meta.maintainers || []
      }
    }
    |> ViewHelpers.include_if_loaded(
      :releases,
      package.releases,
      ReleaseView,
      "minimal.json",
      package: package
    )
    |> ViewHelpers.include_if_loaded(
      :retirements,
      package.releases,
      RetirementView,
      "package.json"
    )
    |> ViewHelpers.include_if_loaded(:downloads, package.downloads, DownloadView, "show.json")
    |> ViewHelpers.include_if_loaded(:owners, package.owners, UserView, "minimal.json")
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
