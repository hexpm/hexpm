defmodule HexpmWeb.Dashboard.SessionController do
  use HexpmWeb, :controller

  alias Hexpm.OAuth.Sessions

  plug :requires_login

  def index(conn, _params) do
    render_index(conn)
  end

  def delete(conn, %{"id" => id}) do
    user = conn.assigns.current_user
    sessions = Sessions.all_for_user(user)

    case Enum.find(sessions, &(&1.id == String.to_integer(id))) do
      nil ->
        conn
        |> put_status(404)
        |> put_flash(:error, "Session not found.")
        |> render_index()

      session ->
        case Sessions.revoke(session) do
          {:ok, _} ->
            conn
            |> put_flash(:info, "The session was revoked successfully.")
            |> redirect(to: ~p"/dashboard/sessions")

          {:error, _} ->
            conn
            |> put_status(400)
            |> put_flash(:error, "Failed to revoke the session.")
            |> render_index()
        end
    end
  end

  defp render_index(conn) do
    user = conn.assigns.current_user
    sessions = Sessions.all_for_user(user)

    render(
      conn,
      "index.html",
      title: "Dashboard - Sessions",
      container: "container page dashboard",
      sessions: sessions
    )
  end
end
