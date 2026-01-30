defmodule HexpmWeb.Dashboard.SessionController do
  use HexpmWeb, :controller

  alias Hexpm.UserSessions

  plug :requires_login

  def index(conn, _params) do
    render_index(conn)
  end

  def delete(conn, %{"id" => id}) do
    case safe_to_integer(id) do
      nil ->
        conn
        |> put_status(404)
        |> put_flash(:error, "Session not found.")
        |> render_index()

      id ->
        delete_session_by_id(conn, id)
    end
  end

  defp delete_session_by_id(conn, id) do
    user = conn.assigns.current_user
    sessions = UserSessions.all_for_user(user)

    case Enum.find(sessions, &(&1.id == id)) do
      nil ->
        conn
        |> put_status(404)
        |> put_flash(:error, "Session not found.")
        |> render_index()

      session ->
        # Prevent deleting current browser session
        current_session_token = get_session(conn, "session_token")

        is_current_session =
          session.type == "browser" && current_session_token &&
            case Base.decode64(current_session_token) do
              {:ok, token} -> token == session.session_token
              _ -> false
            end

        if is_current_session do
          conn
          |> put_flash(:error, "Cannot revoke your current session. Please log out instead.")
          |> redirect(to: ~p"/dashboard/sessions")
        else
          case UserSessions.revoke(session, nil, audit: audit_data(conn)) do
            {:ok, _} ->
              session_type = if session.type == "browser", do: "browser", else: "OAuth"

              conn
              |> put_flash(:info, "The #{session_type} session was revoked successfully.")
              |> redirect(to: ~p"/dashboard/sessions")

            {:error, _} ->
              conn
              |> put_status(400)
              |> put_flash(:error, "Failed to revoke the session.")
              |> render_index()
          end
        end
    end
  end

  defp render_index(conn) do
    user = conn.assigns.current_user
    sessions = UserSessions.all_for_user(user)

    render(
      conn,
      "index.html",
      title: "Dashboard - Sessions",
      container: "container page dashboard",
      sessions: sessions
    )
  end
end
