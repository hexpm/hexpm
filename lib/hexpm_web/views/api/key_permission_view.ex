defmodule HexpmWeb.API.KeyPermissionView do
  use HexpmWeb, :view

  def render("show." <> _, %{key_permission: key_permission}) do
    render_one(key_permission, __MODULE__, "show")
  end

  def render("show", %{key_permission: key_permission}) do
    %{
      domain: key_permission.domain,
      resource: key_permission.resource
    }
  end
end
