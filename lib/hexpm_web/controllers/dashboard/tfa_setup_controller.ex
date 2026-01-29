defmodule HexpmWeb.Dashboard.TFAAuthSetupController do
  use HexpmWeb, :controller

  alias Hexpm.Accounts.{TFA, User}

  plug :requires_login

  def index(conn, _params) do
    user = conn.assigns.current_user

    if User.tfa_enabled?(user) do
      conn
      |> put_flash(:info, "Two-factor authentication is already enabled.")
      |> redirect(to: ~p"/dashboard/security")
    else
      {conn, secret} =
        case get_session(conn, :tfa_setup_secret) do
          nil ->
            secret = TFA.generate_secret()
            {put_session(conn, :tfa_setup_secret, secret), secret}

          secret ->
            {conn, secret}
        end

      render(
        conn,
        "index.html",
        title: "Dashboard - Two-factor authentication setup",
        container: "container page dashboard",
        tfa_secret: secret
      )
    end
  end

  def create(conn, %{"verification_code" => verification_code}) do
    user = conn.assigns.current_user

    if User.tfa_enabled?(user) do
      conn
      |> put_flash(:info, "Two-factor authentication is already enabled.")
      |> redirect(to: ~p"/dashboard/security")
    else
      secret = get_session(conn, :tfa_setup_secret)

      result =
        if secret do
          Users.tfa_enable(user, secret, verification_code, audit: audit_data(conn))
        else
          :error
        end

      case result do
        {:ok, _user} ->
          conn
          |> delete_session(:tfa_setup_secret)
          |> put_flash(:info, "Two-factor authentication has been enabled.")
          |> redirect(to: ~p"/dashboard/security")

        :error ->
          conn
          |> put_flash(:error, "Your verification code was incorrect.")
          |> redirect(to: ~p"/dashboard/tfa/setup")
      end
    end
  end
end
