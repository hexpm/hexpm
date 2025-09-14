defmodule HexpmWeb.TFAAuthController do
  use HexpmWeb, :controller
  require Logger
  alias HexpmWeb.Plugs.Attack

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
      Logger.warning("Failed 2FA attempt",
        user_id: uid,
        ip: conn.remote_ip |> :inet.ntoa() |> to_string(),
        user_agent: get_req_header(conn, "user-agent") |> List.first()
      )

      ip_result = Attack.tfa_ip_throttle(conn.remote_ip)
      session_result = Attack.tfa_session_throttle(session)

      case {ip_result, session_result} do
        {{:block, _}, _} ->
          conn
          |> delete_session("tfa_user_id")
          |> put_flash(:error, "Too many 2FA attempts from your IP. Please try again later.")
          |> redirect(to: ~p"/login")

        {_, {:block, _}} ->
          conn
          |> delete_session("tfa_user_id")
          |> put_flash(:error, "Too many incorrect codes. Please log in again.")
          |> redirect(to: ~p"/login")

        _ ->
          render_show_error(conn)
      end
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
