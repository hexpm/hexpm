defmodule HexWeb.API.IndexView do
  use HexWeb.Web, :view

  def render("index." <> _format, _assigns) do
    %{packages_url: api_package_url(Endpoint, :index),
      package_url: api_package_url(Endpoint, :show, "{name}"),
      package_release_url: api_release_url(Endpoint, :show, "{name}", "{version}"),
      package_owners_url: api_owner_url(Endpoint, :index, "{name}"),
      keys_url: api_key_url(Endpoint, :index),
      key_url: api_key_url(Endpoint, :show, "{name}"),
      documentation_url: "http://docs.hexpm.apiary.io"}
  end
end
