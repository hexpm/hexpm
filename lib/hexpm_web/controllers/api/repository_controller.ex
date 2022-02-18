defmodule HexpmWeb.API.RepositoryController do
  use HexpmWeb, :controller

  plug :fetch_repository when action in [:show]
  plug :authorize, [domain: "api", resource: "read"] when action in [:index]

  plug :authorize,
       [domain: "api", resource: "read", fun: &organization_access/2]
       when action in [:show]

  def index(conn, _params) do
    repositories =
      Repositories.all_public() ++
        all_by_user(conn.assigns.current_user) ++
        all_by_organization(conn.assigns.current_organization)

    when_stale(conn, repositories, [modified: false], fn conn ->
      conn
      |> api_cache(:logged_in)
      |> render(:index, repositories: repositories)
    end)
  end

  def show(conn, _params) do
    repository = conn.assigns.repository

    when_stale(conn, repository, fn conn ->
      conn
      |> api_cache(show_cachability(repository))
      |> render(:show, repository: repository)
    end)
  end

  defp all_by_user(nil) do
    []
  end

  defp all_by_user(user) do
    Enum.map(Organizations.all_by_user(user, [:repository]), & &1.repository)
  end

  defp all_by_organization(nil), do: []
  defp all_by_organization(organization), do: [organization.repository]

  defp show_cachability(%Repository{id: 1}), do: :public
  defp show_cachability(%Repository{}), do: :private
end
