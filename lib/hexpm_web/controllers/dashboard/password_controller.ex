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
        breached? = Hexpm.Pwned.password_breached?(params["user"]["password"])

        conn
        |> put_flash(:info, "Your password has been updated.")
        |> maybe_put_flash(breached?)
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

  defp maybe_put_flash(conn, false), do: conn

  defp maybe_put_flash(conn, true) do
    put_flash(conn, :raw_error, password_breached_message(conn, []))
  end
end
