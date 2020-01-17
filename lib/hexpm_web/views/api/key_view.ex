defmodule HexpmWeb.API.KeyView do
  use HexpmWeb, :view
  alias HexpmWeb.API.KeyPermissionView

  def render("index." <> _, %{keys: keys, authing_key: authing_key}) do
    render_many(keys, __MODULE__, "show", authing_key: authing_key)
  end

  def render("show." <> _, %{key: key, authing_key: authing_key}) do
    render_one(key, __MODULE__, "show", authing_key: authing_key)
  end

  def render("delete." <> _, %{key: key, authing_key: authing_key}) do
    render_one(key, __MODULE__, "show", authing_key: authing_key)
  end

  def render("show", %{key: key, authing_key: authing_key}) do
    %{
      name: key.name,
      authing_key: !!(authing_key && key.id == authing_key.id),
      secret: key.user_secret,
      permissions: render_many(key.permissions, KeyPermissionView, "show.json"),
      revoked_at: key.revoked_at,
      inserted_at: key.inserted_at,
      updated_at: key.updated_at,
      url: Routes.api_key_url(Endpoint, :show, key)
    }
    |> ViewHelpers.include_if_loaded(:last_use, key.last_use, &render_use/1)
  end

  defp render_use(use) do
    %{
      used_at: use.used_at,
      ip: use.ip,
      user_agent: use.user_agent
    }
  end
end
