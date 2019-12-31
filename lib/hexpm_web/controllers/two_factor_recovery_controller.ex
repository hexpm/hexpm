defmodule HexpmWeb.TwoFactorRecoveryController do
  use HexpmWeb, :controller

  plug :authenticate

  def show(conn, _params), do: render_show(conn)

  def create(conn, %{"code" => code}) do
    %{"uid" => uid} = session = get_session(conn, "two_factor_user_id")
    user = Hexpm.Accounts.Users.get_by_id(uid)

    with :ok <- validate_code(code),
         {:ok, updated_user} <- Hexpm.Accounts.Users.tfa_recover(user, code) do
      conn
      |> delete_session("two_factor_user_id")
      |> HexpmWeb.LoginController.start_session(updated_user, session["return"])
    else
      _ ->
        render_show_error(conn)
    end
  end

  defp render_show(conn) do
    render(
      conn,
      "show.html",
      title: "Two Factor Recovery",
      container: "container page page-xs login"
    )
  end

  defp render_show_error(conn) do
    msg = "The recovery code you provided is incorrect. Please try again."

    conn
    |> put_flash(:error, msg)
    |> render_show()
  end

  defp authenticate(conn, _opts) do
    case get_session(conn, "two_factor_user_id") do
      nil ->
        conn |> redirect(to: "/") |> halt()

      _ ->
        conn
    end
  end

  defp validate_code(<<_code::binary-size(19)>>), do: :ok
  defp validate_code(_code), do: :error
end
