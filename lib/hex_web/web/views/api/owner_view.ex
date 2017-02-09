defmodule HexWeb.API.OwnerView do
  use HexWeb.Web, :view

  def render("index." <> format, %{owners: owners}) do
    render(HexWeb.API.UserView, "index." <> format, users: owners, show_email: true)
  end
end
