defmodule Hexpm.Web.API.RepositoryController do
  use Hexpm.Web, :controller

  plug :fetch_repository when action in [:show]
  plug :maybe_authorize, [domain: "api"] when action in [:index]
  plug :maybe_authorize, [domain: "api", fun: &repository_access/2] when action in [:show]

  def index(conn, _params) do
    repositories = Repositories.all_public() ++ all_by_user(conn.assigns.current_user)

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

  defp all_by_user(nil), do: []
  defp all_by_user(user), do: Repositories.all_by_user(user)

  defp show_cachability(%Repository{public: true}), do: :public
  defp show_cachability(%Repository{public: false}), do: :private
end
