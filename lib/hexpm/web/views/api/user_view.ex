defmodule Hexpm.Web.API.UserView do
  use Hexpm.Web, :view

  def render("index." <> _, %{users: users}) do
    render_many(users, __MODULE__, "show")
  end
  def render("show." <> _, %{user: user}) do
    render_one(user, __MODULE__, "show")
  end
  def render("me." <> _, %{user: user}) do
    render_one(user, __MODULE__, "me")
  end
  def render("minimal." <> _, %{user: user}) do
    render_one(user, __MODULE__, "minimal")
  end

  def render("show", %{user: user}) do
    %{
      username: user.username,
      full_name: user.full_name,
      handles: handles(user),
      email: User.email(user, :public),
      url: Routes.api_user_url(Endpoint, :show, user),
      inserted_at: user.inserted_at,
      updated_at: user.updated_at,
    }
    |> include_if_loaded(:owned_packages, user.owned_packages, &owned_packages/1)
    |> include_if_loaded(:packages, user.owned_packages, &packages/1)
  end

  def render("me", %{user: user}) do
    render_one(user, __MODULE__, "show")
    |> Map.put(:organizations, organizations(user))
  end

  def render("minimal", %{user: user}) do
    %{
      username: user.username,
      email: User.email(user, :public),
      url: Routes.api_user_url(Endpoint, :show, user),
    }
  end

  def handles(user) do
    Enum.into(UserHandles.render(user), %{}, fn {field, _service, url} ->
      {field, url}
    end)
  end

  # TODO: deprecated
  defp owned_packages(packages) do
    Enum.into(packages, %{}, fn package ->
      {package.name, url_for_package(package)}
    end)
  end

  defp packages(packages) do
    Enum.map(packages, fn package ->
      %{
        name: package.name,
        repository: package.repository.name,
        url: url_for_package(package),
        html_url: html_url_for_package(package)
      }
    end)
  end

  defp organizations(user) do
    Enum.map(user.repository_users, fn ru ->
      %{
        name: ru.repository.name,
        role: ru.role
      }
    end)
  end
end
