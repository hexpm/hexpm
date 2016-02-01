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
      |> Map.put(:url, user_url(HexWeb.Endpoint, :show, user))

    if assoc_loaded?(user.owned_packages) do
      packages = Enum.into(user.owned_packages, %{}, fn package ->
        {package.name, package_url(HexWeb.Endpoint, :show, package)}
      end)

      entity = Map.put(entity, :owned_packages, packages)
    end

    entity
  end
end
