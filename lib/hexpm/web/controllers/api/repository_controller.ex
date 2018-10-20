defmodule HexpmWeb.API.RepositoryController do
  use HexpmWeb, :controller

  plug :fetch_repository when action in [:show]
  plug :maybe_authorize, [domain: "api", resource: "read"] when action in [:index]

  plug :maybe_authorize,
       [domain: "api", resource: "read", fun: &organization_access/2]
       when action in [:show]

  def index(conn, _params) do
    organizations =
      Organizations.all_public() ++
        all_by_user(conn.assigns.current_user) ++
        all_by_organization(conn.assigns.current_organization)

    when_stale(conn, organizations, [modified: false], fn conn ->
      conn
      |> api_cache(:logged_in)
      |> render(:index, organizations: organizations)
    end)
  end

  def show(conn, _params) do
    organization = conn.assigns.organization

    when_stale(conn, organization, fn conn ->
      conn
      |> api_cache(show_cachability(organization))
      |> render(:show, organization: organization)
    end)
  end

  defp all_by_user(nil), do: []
  defp all_by_user(user), do: Organizations.all_by_user(user)

  defp all_by_organization(nil), do: []
  defp all_by_organization(organization), do: [organization]

  defp show_cachability(%Organization{public: true}), do: :public
  defp show_cachability(%Organization{public: false}), do: :private
end
