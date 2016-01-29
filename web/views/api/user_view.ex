defmodule HexWeb.API.UserView do
  use HexWeb.Web, :view
  import Ecto

  def render("index." <> _, %{users: users}),
    do: render_many(users, __MODULE__, "user")
  def render("show." <> _, %{user: user}),
    do: render_one(user, __MODULE__, "user")

  def render("user", %{user: user}) do
    entity = user
      |> Map.take([:username, :email, :inserted_at, :updated_at])
      |> Map.put(:url, api_url(["users", user.username]))

    if assoc_loaded?(user.owned_packages) do
      packages = Enum.into(user.owned_packages, %{}, fn package ->
        {package.name, api_url(["packages", package.name])}
      end)

      entity = Map.put(entity, :owned_packages, packages)
    end

    entity
  end
end
