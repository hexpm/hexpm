defmodule HexpmWeb.API.OrganizationUserView do
  use HexpmWeb, :view
  alias HexpmWeb.API.UserView

  def render("index." <> _, %{organization_users: organization_users} = assigns) do
    Enum.map(organization_users, fn member ->
      render("show", %{user: member.user, role: member.role})
      |> put_tfa(member.user, assigns)
    end)
  end

  def render("show." <> _, %{user: user, role: role} = assigns) do
    render_one(user, UserView, "show")
    |> Map.merge(%{role: role})
    |> put_tfa(user, assigns)
  end

  def render("show", %{organization_user: organization_user}) do
    render("show", %{user: organization_user.user, role: organization_user.role})
  end

  def render("show", %{user: user, role: role}) do
    render_one(user, UserView, "minimal")
    |> Map.merge(%{role: role})
  end

  defp put_tfa(response, user, %{tfa_visible?: true, organization: organization}),
    do:
      Map.put(
        response,
        :tfa_status,
        Hexpm.Accounts.OrganizationTFA.enrollment_status(organization, user)
      )

  defp put_tfa(response, _user, _assigns), do: response
end
