defmodule HexpmWeb.API.RepositoryController do
  use HexpmWeb, :controller

  plug :fetch_repository when action in [:show]

  plug :authorize,
       [domains: [{"api", "read"}]]
       when action in [:index]

  plug :authorize,
       [domains: [{"api", "read"}], fun: {AuthHelpers, :organization_access}]
       when action in [:show]

  def index(conn, _params) do
    repositories =
      (Repositories.all_public() ++
         all_by_user(conn) ++
         all_by_organization(conn.assigns.current_organization))
      |> Enum.sort_by(fn repository ->
        if repository.id == 1, do: {0, nil}, else: {1, repository.name}
      end)

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

  defp all_by_user(conn) do
    case conn.assigns.current_user do
      nil ->
        []

      user ->
        conn
        |> HexpmWeb.SSOEnforcement.reachable(Organizations.all_by_user(user, [:repository]))
        |> Enum.map(& &1.repository)
    end
  end

  defp all_by_organization(nil), do: []
  defp all_by_organization(organization), do: [organization.repository]

  defp show_cachability(%Repository{id: 1}), do: :public
  defp show_cachability(%Repository{}), do: :private
end
