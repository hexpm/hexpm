defmodule HexpmWeb.API.UserContactController do
  use HexpmWeb, :controller

  alias Hexpm.PackageReports
  alias Hexpm.PackageReports.Maintainers

  def show(conn, %{"name" => name}) do
    case Users.get(name, [:emails]) do
      %User{organization_id: nil, service: false, deactivated_at: nil} = user ->
        PackageReports.record_disclosure([user])

        conn
        |> api_cache(:private)
        |> render(:show, contact: Maintainers.contact(user))

      _other ->
        not_found(conn)
    end
  end
end
