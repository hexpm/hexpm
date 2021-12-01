defmodule HexpmWeb.WebAuthView do
  use HexpmWeb, :view

  def render("show.json", %{key: key}) do
    %{
      access_key: Routes.api_key_url(Endpoint, :show, key)
    }
  end
end
