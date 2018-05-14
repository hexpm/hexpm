defmodule Hexpm.Web.API.OwnerView do
  use Hexpm.Web, :view
  alias Hexpm.Web.API.{OwnerView, UserView}

  def render("index." <> _format, %{owners: owners}) do
    render_many(owners, OwnerView, "show")
  end

  def render("show." <> _format, %{owner: owner}) do
    render_one(owner, OwnerView, "show")
  end

  def render("show", %{owner: owner}) do
    render(UserView, "show", user: owner.user)
    |> Map.put(:level, owner.level)
  end
end
