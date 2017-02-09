defmodule HexWeb.API.UserView do
  use HexWeb.Web, :view
  import Ecto

  def render("index." <> _, %{users: users}),
    do: render_many(users, __MODULE__, "user")
  def render("show." <> _, %{user: user}),
    do: render_one(user, __MODULE__, "user")

  def render("user", %{user: user}) do
    user
    |> Map.take([:username, :full_name, :handles, :inserted_at, :updated_at])
    |> Map.put(:email, User.email(user, :public))
    |> Map.put(:url, api_user_url(Endpoint, :show, user))
    |> Map.update!(:handles, &render_handles/1)
    |> if_value(assoc_loaded?(user.owned_packages), &load_owned(&1, user.owned_packages))
  end

  def render_handles(nil), do: %{}
  def render_handles(handles) do
    keys = UserHandles.services |> Enum.map(&elem(&1, 0))
    Map.take(handles, keys)
  end

  defp load_owned(entity, packages) do
    packages =
      Enum.into(packages, %{}, fn package ->
        {package.name, api_package_url(Endpoint, :show, package)}
      end)

    Map.put(entity, :owned_packages, packages)
  end
end
