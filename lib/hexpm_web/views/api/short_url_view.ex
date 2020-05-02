defmodule HexpmWeb.API.ShortURLView do
  use HexpmWeb, :view

  def render("show." <> _, %{short_url: short_url}) do
    render(__MODULE__, "show", short_url: short_url)
  end

  def render("show", %{short_url: short_url}) do
    %{short_url: short_url}
  end
end
