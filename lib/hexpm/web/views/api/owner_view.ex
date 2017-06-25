defmodule Hexpm.Web.API.OwnerView do
  use Hexpm.Web, :view
  alias Hexpm.Web.API.UserView

  def render("index." <> format, %{owners: owners}) do
    render(UserView, "index." <> format, users: owners, show_email: true)
  end
end
