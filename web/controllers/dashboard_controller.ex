defmodule HexWeb.DashboardController do
  use HexWeb.Web, :controller

  plug :requires_login

  def index(conn, _params) do
    redirect(conn, to: dashboard_path(conn, :profile))
  end

  def profile(conn, _params) do
    user = Users.get_by_username(conn.assigns.username)
    render_profile(conn, User.update_profile(user, %{}))
  end

  def update_profile(conn, params) do
    user = Users.get_by_username(conn.assigns.username)

    case Users.update_profile(user, params["user"]) do
      {:ok, user} ->
        render_profile(conn, User.update_profile(user, %{}))
      {:error, changeset} ->
        conn
        |> put_status(400)
        |> render_profile(changeset)
    end
  end

  def password(conn, _params) do
    user = Users.get_by_username(conn.assigns.username)
    render_password(conn, User.update_password(user, %{}))
  end

  def update_password(conn, params) do
    user = Users.get_by_username(conn.assigns.username)

    case Users.update_password(user, params["user"]) do
      {:ok, user} ->
        # TODO: Maybe send an email here?
        conn
        |> put_flash(:info, "Your password has been updated!")
        |> render_password(User.update_password(user, %{}))
      {:error, changeset} ->
        conn
        |> put_status(400)
        |> render_password(changeset)
    end
  end

  defp render_profile(conn, changeset) do
    render conn, "profile.html", [
      title: "Dashboard - Public profile",
      container: "container page dashboard",
      changeset: changeset
    ]
  end

  defp render_password(conn, changeset) do
    render conn, "password.html", [
      title: "Dashboard - Change password",
      container: "container page dashboard",
      changeset: changeset
    ]
  end
end
