defmodule HexpmWeb.API.AdvisoryView do
  use HexpmWeb, :view

  def render("package." <> _, %{advisory: advisory}) do
    render_one(advisory, __MODULE__, "advisory.json")
  end

  def render("release." <> _, %{advisory: advisory}) do
    render_one(advisory, __MODULE__, "advisory.json")
  end

  def render("advisory.json", %{advisory: %{id: id, summary: summary, affected: affected}}) do
    %{
      id: id,
      summary: summary,
      affected: affected,
      api_url: "https://api.osv.dev/v1/vulns/#{URI.encode(id)}",
      html_url: "https://osv.dev/vulnerability/#{URI.encode(id)}"
    }
  end
end
