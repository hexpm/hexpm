defmodule Hexpm.Web.API.OwnerView do
  use Hexpm.Web, :view

  def render("index." <> format, %{owners: owners}) do
    render(Hexpm.Web.API.UserView, "index." <> format, users: owners, show_email: true)
  end
end
