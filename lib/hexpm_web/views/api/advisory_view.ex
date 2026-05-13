defmodule HexpmWeb.API.AdvisoryView do
  use HexpmWeb, :view

  def render("package." <> _, %{advisory: advisory, package: package}) do
    render_one(advisory, __MODULE__, "advisory.json", %{package: package})
  end

  def render("release." <> _, %{advisory: advisory, release: release}) do
    render_one(advisory, __MODULE__, "advisory.json", %{package_id: release.package_id})
  end

  def render("advisory.json", %{advisory: advisory} = assigns) do
    package_id = assigns[:package_id] || (assigns[:package] && assigns.package.id)

    %{
      id: advisory.id,
      summary: advisory.summary,
      aliases: advisory.aliases,
      published_at: advisory.published_at,
      modified_at: advisory.modified_at,
      withdrawn_at: advisory.withdrawn_at,
      cvss_vector: advisory.cvss_vector,
      cvss_score: advisory.cvss_score,
      cvss_rating: advisory.cvss_rating,
      references: render_references(advisory.references),
      affected: render_affected(advisory.affected_versions, package_id),
      api_url: "https://api.osv.dev/v1/vulns/#{URI.encode(advisory.id)}",
      html_url: "https://osv.dev/vulnerability/#{URI.encode(advisory.id)}"
    }
  end

  defp render_references(%Ecto.Association.NotLoaded{}), do: []

  defp render_references(refs) do
    Enum.map(refs, fn ref -> %{type: ref.type, url: ref.url} end)
  end

  defp render_affected(%Ecto.Association.NotLoaded{}, _package_id), do: []

  defp render_affected(_versions, nil), do: []

  defp render_affected(versions, package_id) do
    versions
    |> Enum.filter(&(&1.package_id == package_id))
    |> Enum.map(&to_string(&1.requirement))
  end
end
