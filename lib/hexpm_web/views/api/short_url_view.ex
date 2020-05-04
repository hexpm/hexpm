defmodule HexpmWeb.API.ShortURLView do
  use HexpmWeb, :view

  def render("show." <> _, %{url: url}) do
    render(__MODULE__, "show", url: url)
  end

  def render("show", %{url: url}) do
    %{url: url}
  end
end
