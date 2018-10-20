defmodule HexpmWeb.API.IndexView do
  use HexpmWeb, :view

  def render("index." <> _format, _assigns) do
    %{
      packages_url: Routes.api_package_url(Endpoint, :index),
      package_url: Routes.api_package_url(Endpoint, :show, "{name}") |> fix_placeholder(),
      package_release_url:
        Routes.api_release_url(Endpoint, :show, "{name}", "{version}") |> fix_placeholder(),
      package_owners_url: Routes.api_owner_url(Endpoint, :index, "{name}") |> fix_placeholder(),
      keys_url: Routes.api_key_url(Endpoint, :index),
      key_url: Routes.api_key_url(Endpoint, :show, "{name}") |> fix_placeholder(),
      documentation_url: "http://docs.hexpm.apiary.io"
    }
  end

  defp fix_placeholder(url) do
    url
    |> String.replace("%7B", "{")
    |> String.replace("%7D", "}")
  end
end
