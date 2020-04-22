defmodule HexpmWeb.Dashboard.SecurityController do
  use HexpmWeb, :controller
  alias Hexpm.Accounts.User

  plug :requires_login

  def index(conn, _params) do
    user = conn.assigns.current_user

    if User.tfa_enabled?(user) and not user.tfa.app_enabled do
      conn
      |> put_flash(:error, "Please complete your two-factor authentication setup")
      |> redirect(to: Routes.dashboard_tfa_setup_path(conn, :index))
    else
      render_index(conn)
    end
  end

  def enable_tfa(conn, _params) do
    user = conn.assigns.current_user
    Users.tfa_enable(user, audit: audit_data(conn))

    conn
    |> put_flash(:info, "Two factor authentication has been enabled.")
    |> redirect(to: Routes.dashboard_tfa_setup_path(conn, :index))
  end

  def disable_tfa(conn, _params) do
    user = conn.assigns.current_user
    Users.tfa_disable(user, audit: audit_data(conn))

    conn
    |> put_flash(:info, "Two factor authentication has been disabled.")
    |> redirect(to: Routes.dashboard_security_path(conn, :index))
  end

  def rotate_recovery_codes(conn, _params) do
    user = conn.assigns.current_user
    Users.tfa_rotate_recovery_codes(user, audit: audit_data(conn))

    conn
    |> put_flash(:info, "New two-factor recovery codes successfully generated.")
    |> redirect(to: Routes.dashboard_security_path(conn, :index))
  end

  def reset_auth_app(conn, _params) do
    user = conn.assigns.current_user
    Users.tfa_disable_app(user, audit: audit_data(conn))

    conn
    |> put_flash(:info, "Please complete your two-factor authentication setup")
    |> redirect(to: Routes.dashboard_tfa_setup_path(conn, :index))
  end

  defp render_index(conn) do
    render(
      conn,
      "index.html",
      title: "Dashboard - Security",
      container: "container page dashboard"
    )
  end
end
