defmodule HexWeb.API.UserView do
  use HexWeb.Web, :view
  import Ecto

  def render("index." <> _, %{users: users}),
    do: render_many(users, __MODULE__, "user")
  def render("show." <> _, %{user: user}),
    do: render_one(user, __MODULE__, "user")

  def render("user", %{user: user}) do
    user
    |> Map.take([:username, :email, :inserted_at, :updated_at])
    |> Map.put(:url, user_url(HexWeb.Endpoint, :show, user))
    |> if_value(assoc_loaded?(user.owned_packages), &load_owned(&1, user.owned_packages))
  end

  defp load_owned(entity, packages) do
    packages =
      Enum.into(packages, %{}, fn package ->
        {package.name, package_url(HexWeb.Endpoint, :show, package)}
      end)

    Map.put(entity, :owned_packages, packages)
  end
end
