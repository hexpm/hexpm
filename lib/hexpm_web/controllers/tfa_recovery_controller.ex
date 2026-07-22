defmodule HexpmWeb.TFARecoveryController do
  use HexpmWeb, :controller

  plug :authenticate

  def show(conn, _params), do: render_show(conn)

  def create(conn, %{"code" => code}) do
    %{"uid" => uid} = session = get_session(conn, "tfa_user_id")
    user = Hexpm.Accounts.Users.get_by_id(uid)

    with true <- valid_code?(code),
         {:ok, updated_user} <- Hexpm.Accounts.Users.tfa_recover(user, code) do
      conn
      |> delete_session("tfa_user_id")
      |> start_session_internal(updated_user)
      |> prove_pending_sso_link(updated_user)
      |> HexpmWeb.Plugs.Sudo.set_sudo_authenticated()
      |> then(fn conn ->
        return = safe_return_path(session["return"])

        redirect(conn,
          to: pending_sso_link_return(conn, return) || ~p"/users/#{updated_user}"
        )
      end)
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
    case get_session(conn, "tfa_user_id") do
      %{"at" => at} ->
        if HexpmWeb.Session.TTL.within?(at, minute: 15) do
          conn
        else
          conn |> delete_session("tfa_user_id") |> redirect(to: "/") |> halt()
        end

      _ ->
        conn |> redirect(to: "/") |> halt()
    end
  end

  defp valid_code?(code), do: is_binary(code) and byte_size(code) == 19
end
