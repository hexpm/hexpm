defmodule HexpmWeb.Dashboard.TFAAuthSetupController do
  use HexpmWeb, :controller

  plug :requires_login

  def index(conn, _params) do
    render(
      conn,
      "index.html",
      title: "Dashboard - Two-factor authentication setup",
      container: "container page dashboard"
    )
  end

  def create(conn, %{"verification_code" => verification_code}) do
    user = conn.assigns.current_user

    case Users.tfa_enable_app(user, verification_code, audit: audit_data(conn)) do
      {:ok, _user} ->
        conn
        |> put_flash(:info, "Two-factor authentication has been enabled.")
        |> redirect(to: Routes.dashboard_security_path(conn, :index))

      :error ->
        conn
        |> put_flash(:error, "Your verification code was incorrect.")
        |> redirect(to: Routes.dashboard_tfa_setup_path(conn, :index))
    end
  end
end
