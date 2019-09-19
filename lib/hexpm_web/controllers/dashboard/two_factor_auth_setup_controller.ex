defmodule HexpmWeb.Dashboard.TwoFactorAuthSetupController do
  use HexpmWeb, :controller

  alias Hexpm.Accounts.TwoFactorAuth

  plug :requires_login

  def index(conn, _params) do
    render(
      conn,
      "index.html",
      title: "Dashboard - Two-Factor Authentication Setup",
      container: "container page dashboard",
      qr_code:
        conn.assigns.current_user
        |> TwoFactorAuth.qr_code_content()
        |> TwoFactorAuth.qr_code_svg()
    )
  end
end
