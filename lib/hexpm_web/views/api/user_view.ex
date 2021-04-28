defmodule HexpmWeb.API.UserView do
  use HexpmWeb, :view

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

  def render("audit_logs." <> _, %{audit_logs: audit_logs}) do
    render_many(audit_logs, HexpmWeb.API.AuditLogView, "show")
  end

  def render("show", %{user: user}) do
    %{
      username: user.username,
      full_name: user.full_name,
      handles: handles(user),
      url: Routes.api_user_url(Endpoint, :show, user),
      inserted_at: user.inserted_at,
      updated_at: user.updated_at
    }
    |> put_maybe(:email, User.email(user, :public))
    |> ViewHelpers.include_if_loaded(:owned_packages, user.owned_packages, &owned_packages/1)
    |> ViewHelpers.include_if_loaded(:packages, user.owned_packages, &packages/1)
  end

  def render("me", %{user: user}) do
    render_one(user, __MODULE__, "show")
    |> Map.put(:organizations, organizations(user))
  end

  def render("minimal", %{user: user}) do
    %{
      username: user.username,
      url: Routes.api_user_url(Endpoint, :show, user)
    }
    |> put_maybe(:email, User.email(user, :public))
  end

  def handles(user) do
    Enum.into(UserHandles.render(user), %{}, fn {field, _service, url} ->
      {field, url}
    end)
  end

  # TODO: deprecated
  defp owned_packages(packages) do
    Enum.into(packages, %{}, fn package ->
      {package.name, ViewHelpers.url_for_package(package)}
    end)
  end

  defp packages(packages) do
    packages
    |> Enum.sort_by(&[repository_sort(&1), &1.name])
    |> Enum.map(fn package ->
      %{
        name: package.name,
        repository: repository_name(package),
        url: ViewHelpers.url_for_package(package),
        html_url: ViewHelpers.html_url_for_package(package)
      }
    end)
  end

  defp repository_name(%Package{repository_id: 1}), do: "hexpm"
  defp repository_name(%Package{repository: %Repository{name: name}}), do: name

  # TODO: DRY up
  # Atoms sort before strings
  defp repository_sort(%Package{repository_id: 1}), do: :first
  defp repository_sort(%Package{repository: %Repository{name: name}}), do: name

  defp organizations(user) do
    Enum.map(user.organization_users, fn ru ->
      %{
        name: ru.organization.name,
        role: ru.role
      }
    end)
  end

  defp put_maybe(map, _key, nil), do: map
  defp put_maybe(map, key, value), do: Map.put(map, key, value)
end
