defmodule HexpmWeb.API.IndexView do
  use HexpmWeb, :view

  def render("index." <> _format, _assigns) do
    %{
      packages_url: url(~p"/api/packages"),
      package_url: fix_placeholder(url(~p"/api/packages/{name}")),
      package_release_url: fix_placeholder(url(~p"/api/packages/{name}/releases/{version}")),
      package_owners_url: fix_placeholder(url(~p"/api/packages/{name}/owners")),
      keys_url: url(~p"/api/keys"),
      key_url: fix_placeholder(url(~p"/api/keys/{name}")),
      documentation_url: "http://docs.hexpm.apiary.io"
    }
  end

  defp fix_placeholder(url) do
    url
    |> String.replace("%7B", "{")
    |> String.replace("%7D", "}")
  end
end
