defmodule HexpmWeb.Dashboard.PasswordController do
  use HexpmWeb, :controller

  plug :requires_login

  def index(conn, _params) do
    user = conn.assigns.current_user
    render_index(conn, User.update_password(user, %{}))
  end

  def update(conn, params) do
    user = conn.assigns.current_user

    case Users.update_password(user, params["user"], audit: audit_data(conn)) do
      {:ok, _user} ->
        conn
        |> put_flash(:info, "Your password has been updated.")
        |> redirect(to: Routes.dashboard_password_path(conn, :index))

      {:error, changeset} ->
        conn
        |> put_status(400)
        |> render_index(changeset)
    end
  end

  defp render_index(conn, changeset) do
    render(
      conn,
      "index.html",
      title: "Dashboard - Change password",
      container: "container page dashboard",
      changeset: changeset
    )
  end
end
