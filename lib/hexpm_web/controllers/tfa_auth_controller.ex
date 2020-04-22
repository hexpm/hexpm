defmodule HexpmWeb.TFAAuthController do
  use HexpmWeb, :controller

  plug :authenticate

  def show(conn, _params), do: render_show(conn)

  def create(conn, %{"code" => code}) do
    %{"uid" => uid} = session = get_session(conn, "tfa_user_id")
    user = Hexpm.Accounts.Users.get_by_id(uid)
    secret = user.tfa.secret

    if Hexpm.Accounts.TFA.token_valid?(secret, code) do
      conn
      |> delete_session("tfa_user_id")
      |> HexpmWeb.LoginController.start_session(user, session["return"])
    else
      render_show_error(conn)
    end
  end

  defp render_show(conn) do
    render(
      conn,
      "show.html",
      title: "Two Factor Authentication",
      container: "container page page-xs login"
    )
  end

  defp render_show_error(conn) do
    msg = "The verification code you provided is incorrect. Please try again."

    conn
    |> put_flash(:error, msg)
    |> render_show()
  end

  defp authenticate(conn, _opts) do
    case get_session(conn, "tfa_user_id") do
      nil ->
        conn |> redirect(to: "/") |> halt()

      _ ->
        conn
    end
  end
end
