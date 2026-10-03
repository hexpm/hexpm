defmodule HexpmWeb.TFAAuthController do
  use HexpmWeb, :controller
  alias Hexpm.SecurityLog
  alias HexpmWeb.Plugs.Attack

  plug :authenticate

  def show(conn, _params), do: render_show(conn)

  def create(conn, %{"code" => code}) do
    %{"uid" => uid} = session_data = get_session(conn, "tfa_user_id")
    user = Hexpm.Accounts.Users.get_by_id(uid, [:emails, organizations: :repository])

    case check_rate_limits(conn, uid, increment: 0) do
      :ok -> verify_code(conn, user, session_data, code)
      {:rate_limited, scope} -> rate_limited(conn, session_data, scope)
    end
  end

  defp verify_code(conn, user, session_data, code) do
    if Hexpm.Accounts.TFA.token_valid?(user.tfa.secret, code) do
      conn
      |> delete_session("tfa_user_id")
      |> start_session_internal(user)
      |> HexpmWeb.Plugs.Sudo.set_sudo_authenticated()
      |> redirect(to: safe_return_path(session_data["return"]) || ~p"/users/#{user}")
    else
      SecurityLog.auth_failure(conn, :tfa, :invalid_code, user_id: user.id)

      case check_rate_limits(conn, user.id) do
        :ok -> render_show_error(conn)
        {:rate_limited, scope} -> rate_limited(conn, session_data, scope)
      end
    end
  end

  defp check_rate_limits(conn, user_id, opts \\ []) do
    ip_result = Attack.tfa_ip_throttle(conn.remote_ip, opts)
    user_result = Attack.tfa_user_throttle(user_id, opts)

    case {ip_result, user_result} do
      {{:block, _}, _} -> {:rate_limited, :ip}
      {_, {:block, _}} -> {:rate_limited, :user}
      _ -> :ok
    end
  end

  defp rate_limited(conn, session_data, :ip) do
    conn
    |> delete_session("tfa_user_id")
    |> put_flash(:error, "Too many 2FA attempts from your IP. Please try again later.")
    |> redirect(to: login_path(session_data["return"]))
  end

  defp rate_limited(conn, session_data, :user) do
    conn
    |> delete_session("tfa_user_id")
    |> put_flash(:error, "Too many incorrect codes. Please log in again.")
    |> redirect(to: login_path(session_data["return"]))
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
end
