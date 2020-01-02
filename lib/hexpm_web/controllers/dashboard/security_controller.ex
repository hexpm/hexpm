defmodule HexpmWeb.Dashboard.SecurityController do
  use HexpmWeb, :controller

  plug :requires_login

  def index(conn, _params) do
    user = conn.assigns.current_user
    render_index(conn, User.update_security(user, %{}))
  end

  def update(conn, params) do
    user = conn.assigns.current_user
    updated_setting = params["user"]["tfa_enabled"]

    case {user.tfa_enabled, updated_setting} do
      {false, "true"} ->
        # need to redirect to the QR code setup page
        update_tfa_setting(user, conn, false, true)

      {true, "false"} ->
        update_tfa_setting(user, conn, true, false)

      change ->
        conn
        |> put_flash(:info, "Your security preference has been updated.")
        |> redirect(to: Routes.dashboard_security_path(conn, :index))
    end
  end

  def rotate_recovery_codes(conn, _params) do
    user = conn.assigns.current_user

    case Users.rotate_recovery_codes(user, audit: audit_data(conn)) do
      {:ok, _user} ->
        conn
        |> put_flash(:info, "New two-factor recovery codes successfully generated.")
        |> redirect(to: Routes.dashboard_security_path(conn, :index))

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
      title: "Dashboard - Security",
      container: "container page dashboard",
      changeset: changeset
    )
  end

  defp update_tfa_setting(user, conn, true, false) do
    case Users.update_security(user, %{"tfa_enabled" => "false"}, audit: audit_data(conn)) do
      {:ok, _user} ->
        conn
        |> put_flash(:info, "Your security preference has been updated.")
        |> redirect(to: Routes.dashboard_security_path(conn, :index))

      {:error, changeset} ->
        conn
        |> put_status(400)
        |> render_index(changeset)
    end
  end

  defp update_tfa_setting(user, conn, false, true) do
    case Users.update_security(user, %{"tfa_enabled" => "true"}, audit: audit_data(conn)) do
      {:ok, _user} ->
        conn
        |> put_flash(:info, "Your security preference has been updated.")
        |> redirect(to: Routes.dashboard_two_factor_auth_setup_path(conn, :index))

      {:error, changeset} ->
        conn
        |> put_status(400)
        |> render_index(changeset)
    end
  end
end
