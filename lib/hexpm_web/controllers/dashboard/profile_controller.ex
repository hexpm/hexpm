defmodule HexpmWeb.Dashboard.ProfileController do
  use HexpmWeb, :controller

  plug :requires_login
  plug :requires_verified_primary_email

  def index(conn, _params) do
    user = conn.assigns.current_user
    render_index(conn, User.update_profile(user, %{}))
  end

  def update(conn, params) do
    user = conn.assigns.current_user

    case Users.update_profile(user, params["user"], audit: audit_data(conn)) do
      {:ok, _user} ->
        conn
        |> put_flash(:info, "Profile updated successfully.")
        |> redirect(to: ~p"/dashboard/profile")

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
      title: "Dashboard - Public profile",
      container: "flex-1 flex flex-col",
      changeset: changeset
    )
  end

  defp requires_verified_primary_email(conn, _opts) do
    if User.verified_primary_email?(conn.assigns.current_user) do
      conn
    else
      conn
      |> put_flash(:error, "Verify your primary email before editing your public profile.")
      |> redirect(to: ~p"/dashboard/email")
      |> halt()
    end
  end
end
