defmodule HexWeb.API.KeyView do
  use HexWeb.Web, :view

  def render("index." <> _, %{keys: keys}),
    do: render_many(keys, __MODULE__, "key")
  def render("show." <> _, %{key: key}),
    do: render_one(key, __MODULE__, "key")
  def render("delete." <> _, %{key: key}),
    do: render_one(key, __MODULE__, "key")

  def render("key", %{key: key}) do
    entity =
      if key.revoked_at do
        %{
          name: key.revoked_name,
          revoked_at: key.revoked_at
        }
      else
        key
        |> Map.take([:name, :inserted_at, :updated_at])
        |> Map.put(:url, key_url(HexWeb.Endpoint, :show, key))
      end

    if secret = key.user_secret do
      Map.put(entity, :secret, secret)
    else
      entity
    end
  end
end
