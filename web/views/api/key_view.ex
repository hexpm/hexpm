defmodule HexWeb.API.KeyView do
  use HexWeb.Web, :view

  def render("index." <> _, %{keys: keys, authing_key: authing_key}),
    do: render_many(keys, __MODULE__, "key", authing_key: authing_key)
  def render("show." <> _, %{key: key, authing_key: authing_key}),
    do: render_one(key, __MODULE__, "key", authing_key: authing_key)
  def render("delete." <> _, %{key: key, authing_key: authing_key}),
    do: render_one(key, __MODULE__, "key", authing_key: authing_key)

  def render("key", %{key: key, authing_key: authing_key}) do
    entity =
      key
      |> Map.take([:name, :inserted_at, :updated_at, :revoked_at])
      |> Map.put(:authing_key, !!(authing_key && key.id == authing_key.id))

    if is_nil(key.revoked_at) do
      if secret = key.user_secret do
        Map.put(entity, :secret, secret)
      else
        entity
      end
      |> Map.put(:url, api_key_url(Endpoint, :show, key))
    else
      entity
    end
  end
end
