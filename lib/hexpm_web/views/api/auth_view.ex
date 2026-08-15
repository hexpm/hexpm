defmodule HexpmWeb.API.AuthView do
  use HexpmWeb, :view

  def render("show." <> _, %{key: key}) do
    %{
      key: %{
        name: key.name,
        owner: render_owner(key)
      }
    }
  end

  defp render_owner(%Key{organization: %Organization{} = organization}) do
    %{type: "organization", name: organization.name}
  end

  defp render_owner(%Key{user: %User{} = user}) do
    %{type: "user", name: user.username}
  end
end
