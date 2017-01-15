defmodule HexWeb.API.IndexView do
  use HexWeb.Web, :view

  def render("index." <> _format, _assigns) do
    %{packages_url: api_package_url(Endpoint, :index),
      documentation_url: "http://docs.hexpm.apiary.io"}
  end
end
