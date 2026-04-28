defmodule HexpmWeb.SudoController do
  use HexpmWeb, :controller
  require Logger

  alias Hexpm.Accounts.{TFA, Users}
  alias HexpmWeb.Plugs.{Attack, Sudo}

  plug :requires_login

  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show(conn, _params) do
    if Sudo.sudo_active?(conn) do
      return_to = get_session(conn, "sudo_return_to") || ~p"/dashboard/security"

      conn
      |> delete_session("sudo_return_to")
      |> redirect(to: return_to)
    else
      render_show(conn)
    end
  end

  @spec show_recovery(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show_recovery(conn, _params) do
    user = conn.assigns.current_user

    if User.tfa_enabled?(user) do
      render_recovery(conn)
    else
      conn
      |> put_flash(:error, "Two-factor authentication is not enabled.")
      |> redirect(to: ~p"/sudo")
    end
  end

  @spec create(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def create(conn, %{"type" => "password", "password" => password}) do
    user = conn.assigns.current_user

    if User.tfa_enabled?(user) do
      conn
      |> put_flash(:error, "Please use your authenticator app or recovery code.")
      |> render_show()
    else
      verify_password(conn, user, password)
    end
  end

  def create(conn, %{"type" => "tfa", "code" => code}) do
    user = conn.assigns.current_user

    if User.tfa_enabled?(user) do
      verify_tfa(conn, user, code)
    else
      conn
      |> put_flash(:error, "Two-factor authentication is not enabled.")
      |> render_show()
    end
  end

  def create(conn, _params) do
    conn
    |> put_flash(:error, "Invalid verification request.")
    |> render_show()
  end

  @spec verify_recovery(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def verify_recovery(conn, %{"code" => code}) do
    user = conn.assigns.current_user

    if User.tfa_enabled?(user) do
      do_verify_recovery(conn, user, code)
    else
      conn
      |> put_flash(:error, "Two-factor authentication is not enabled.")
      |> redirect(to: ~p"/sudo")
    end
  end

  @spec github(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def github(conn, _params) do
    user = conn.assigns.current_user

    if User.tfa_enabled?(user) do
      conn
      |> put_flash(:error, "Please use your authenticator app or recovery code.")
      |> redirect(to: ~p"/sudo")
    else
      user = Hexpm.Repo.preload(user, :user_providers)

      if Enum.any?(user.user_providers, &(&1.provider == "github")) do
        conn
        |> put_session("sudo_verification", true)
        |> redirect(to: ~p"/auth/github")
      else
        conn
        |> put_flash(:error, "No GitHub account linked.")
        |> redirect(to: ~p"/sudo")
      end
    end
  end

  @spec verify_password(Plug.Conn.t(), User.t(), String.t()) :: Plug.Conn.t()
  defp verify_password(conn, user, password) do
    case Attack.sudo_password_throttle(user.id) do
      {:block, _data} ->
        conn
        |> put_flash(:error, "Too many incorrect password attempts. Please try again later.")
        |> render_show()

      {:allow, _data} ->
        if correct_password?(user, password) do
          redirect_after_sudo(conn)
        else
          Logger.warning("Failed sudo password attempt",
            user_id: user.id,
            ip: conn.remote_ip |> :inet.ntoa() |> to_string(),
            user_agent: get_req_header(conn, "user-agent") |> List.first()
          )

          conn
          |> put_flash(:error, "Incorrect password.")
          |> render_show()
        end
    end
  end

  @spec verify_tfa(Plug.Conn.t(), User.t(), String.t()) :: Plug.Conn.t()
  defp verify_tfa(conn, user, code) do
    case Attack.sudo_tfa_throttle(user.id) do
      {:block, _data} ->
        conn
        |> put_flash(:error, "Too many incorrect code attempts. Please try again later.")
        |> render_show()

      {:allow, _data} ->
        if TFA.token_valid?(user.tfa.secret, code) do
          redirect_after_sudo(conn)
        else
          Logger.warning("Failed sudo 2FA attempt",
            user_id: user.id,
            ip: conn.remote_ip |> :inet.ntoa() |> to_string(),
            user_agent: get_req_header(conn, "user-agent") |> List.first()
          )

          conn
          |> put_flash(:error, "Incorrect authentication code.")
          |> render_show()
        end
    end
  end

  @spec do_verify_recovery(Plug.Conn.t(), User.t(), String.t()) :: Plug.Conn.t()
  defp do_verify_recovery(conn, user, code) do
    case Attack.sudo_tfa_throttle(user.id) do
      {:block, _data} ->
        conn
        |> put_flash(:error, "Too many incorrect code attempts. Please try again later.")
        |> render_recovery()

      {:allow, _data} ->
        if valid_recovery_code?(code) do
          case Users.tfa_recover(user, code) do
            {:ok, _user} ->
              redirect_after_sudo(conn)

            _ ->
              Logger.warning("Failed sudo recovery code attempt",
                user_id: user.id,
                ip: conn.remote_ip |> :inet.ntoa() |> to_string(),
                user_agent: get_req_header(conn, "user-agent") |> List.first()
              )

              conn
              |> put_flash(:error, "Incorrect recovery code.")
              |> render_recovery()
          end
        else
          conn
          |> put_flash(:error, "Invalid recovery code format.")
          |> render_recovery()
        end
    end
  end

  @spec redirect_after_sudo(Plug.Conn.t()) :: Plug.Conn.t()
  defp redirect_after_sudo(conn) do
    return_to = get_session(conn, "sudo_return_to") || ~p"/dashboard/security"

    conn
    |> Sudo.set_sudo_authenticated()
    |> delete_session("sudo_return_to")
    |> redirect(to: return_to)
  end

  @spec render_show(Plug.Conn.t()) :: Plug.Conn.t()
  defp render_show(conn) do
    user = Hexpm.Repo.preload(conn.assigns.current_user, :user_providers)

    render(
      conn,
      "show.html",
      title: "Verify your identity",
      container: "container page page-xs login",
      tfa_enabled: User.tfa_enabled?(user),
      has_password: User.has_password?(user),
      has_github: Enum.any?(user.user_providers, &(&1.provider == "github"))
    )
  end

  @spec render_recovery(Plug.Conn.t()) :: Plug.Conn.t()
  defp render_recovery(conn) do
    render(
      conn,
      "recovery.html",
      title: "Enter recovery code",
      container: "container page page-xs login"
    )
  end

  @spec correct_password?(User.t(), String.t()) :: boolean()
  defp correct_password?(%User{password: nil}, _password), do: false

  defp correct_password?(%User{password: hash}, password) do
    Bcrypt.verify_pass(password, hash)
  end

  @spec valid_recovery_code?(term()) :: boolean()
  defp valid_recovery_code?(code), do: is_binary(code) and byte_size(code) == 19
end
