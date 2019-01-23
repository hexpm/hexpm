defmodule HexpmWeb.API.OrganizationUserView do
  use HexpmWeb, :view
  alias HexpmWeb.API.UserView

  def render("index." <> _, %{organization_users: organization_users}) do
    render_many(organization_users, __MODULE__, "show")
  end

  def render("show." <> _, %{user: user, role: role}) do
    render_one(user, UserView, "show")
    |> Map.merge(%{role: role})
  end

  def render("show", %{organization_user: organization_user}) do
    render("show", %{user: organization_user.user, role: organization_user.role})
  end

  def render("show", %{user: user, role: role}) do
    render_one(user, UserView, "minimal")
    |> Map.merge(%{role: role})
  end
end
