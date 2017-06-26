defmodule Hexpm.Web.API.KeyView do
  use Hexpm.Web, :view

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
      revoked_at: key.revoked_at,
      inserted_at: key.inserted_at,
      updated_at: key.updated_at,
      url: api_key_url(Endpoint, :show, key)
    }
  end
end
