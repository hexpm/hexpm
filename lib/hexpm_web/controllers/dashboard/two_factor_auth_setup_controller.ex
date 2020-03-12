defmodule HexpmWeb.Dashboard.TwoFactorAuthSetupController do
  use HexpmWeb, :controller

  alias Hexpm.Accounts.User

  plug :requires_login

  def index(conn, params) do
    user = conn.assigns.current_user
    changeset = User.update_two_factor_auth(user, params)

    render(
      conn,
      "index.html",
      title: "Dashboard - Two-Factor Authentication Setup",
      container: "container page dashboard",
      changeset: changeset
    )
  end
end
