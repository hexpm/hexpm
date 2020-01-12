defmodule HexpmWeb.Dashboard.AuditLogController do
  use HexpmWeb, :controller

  plug :requires_login

  def index(conn, _params) do
    conn
    |> render(
      "index.html",
      title: "Dashboard - Recent activities",
      container: "container page dashboard"
    )
  end
end
