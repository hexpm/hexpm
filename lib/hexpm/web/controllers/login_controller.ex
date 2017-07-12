defmodule Hexpm.Web.LoginController do
  use Hexpm.Web, :controller

  plug :nillify_params, ["return"]

  def show(conn, _params) do
    if session_exists?(conn) do
      case halfopen?(conn) do
        :expired -> # close session if over threshold
          expire_session(conn)

        :fullyopen -> # session is already open
          path = conn.params["return"] || user_path(conn, :show, conn.assigns.logged_in)
          redirect(conn, to: path)

        :halfopen -> # session requires 2fa
          path = login_path(conn, :show_twofactor_totp, return: conn.params["return"])
          redirect(conn, to: path)
      end
    else
      render_show(conn)
    end
  end

  def show_twofactor_totp(conn, _params) do
    if session_exists?(conn) do
      case halfopen?(conn) do
        :expired -> # close session if over threshold
          expire_session(conn)

        :fullyopen -> # session is already open
          path = conn.params["return"] || user_path(conn, :show, conn.assigns.logged_in)
          redirect(conn, to: path)

        :halfopen -> # session requires 2fa
          render_show_twofactor_totp(conn)
      end
    else
      redirect(conn, to: login_path(conn, :show))
    end
  end

  def show_sudo(conn, _params) do
    if logged_in?(conn) do
      if sudomode?(conn) do
        path = conn.params["return"] || user_path(conn, :show, conn.assigns.logged_in)
        redirect(conn, to: path)
      else
        render_sudo(conn)
      end
    else
      redirect(conn, to: login_path(conn, :show))
    end
  end

  def create(conn, %{"username" => username, "password" => password}) do
    case password_auth(username, password) do
      {:ok, user} ->
        if TwoFactor.enabled?(user.twofactor) do
          path = login_path(conn, :show_twofactor_totp, return: conn.params["return"]) # pass return parameter

          conn
          |> configure_session(renew: true)
          |> put_session("user_id", user.id)
          |> halfopen(:enable) # set session to halfopen state
          |> redirect(to: path)
        else
          path = conn.params["return"] || user_path(conn, :show, user)

          conn
          |> configure_session(renew: true)
          |> put_session("user_id", user.id)
          |> redirect(to: path)
        end

      {:error, reason} ->
        conn
        |> put_flash(:error, auth_error_message(reason))
        |> put_status(400)
        |> render_show
    end
  end

  def create_twofactor_totp(conn, %{"otp" => otp}) do
    return = conn.params["return"] || user_path(conn, :show, conn.assigns[:logged_in])

    if session_exists?(conn) do # check session exists
      case halfopen?(conn) do
        :expired -> # close session if over threshold
          expire_session(conn)

        :fullyopen -> # session is already open
          redirect(conn, to: return)

        :halfopen -> # session requires 2fa
          case Auth.twofactor_auth(conn.assigns[:logged_in], otp) do
            {:ok, user} ->
              # set user.twofactor.data.last to otp to prevent reuse
              case set_last_otp(conn, user, otp) do
                :ok ->
                  conn
                  |> halfopen(:disable) # fully open session
                  |> redirect(to: return)

                :error ->
                  conn
                  |> put_flash(:error, auth_error_message(:twofactor, :incorrect))
                  |> put_status(400)
                  |> render_show_twofactor_totp
              end

            {:backupcode, user, code} ->
              # delete code from user.twofactor.data.backupcodes
              case use_backup_code(conn, user, code) do
                :ok ->
                  conn
                  |> halfopen(:disable) # fully open session
                  |> redirect(to: return)

                :error ->
                  conn
                  |> put_flash(:error, auth_error_message(:twofactor, :incorrect))
                  |> put_status(400)
                  |> render_show_twofactor_totp
              end

            :error ->
              conn
              |> put_flash(:error, auth_error_message(:twofactor, :incorrect))
              |> put_status(400)
              |> render_show_twofactor_totp
          end
      end
    else
      redirect(conn, to: login_path(conn, :show))
    end
  end

  def create_sudo(conn, %{"password" => password}) do
    if logged_in?(conn) do
      user = conn.assigns[:logged_in]
      path = conn.params["return"] || user_path(conn, :show, user)

      case password_auth(user.username, password) do
        {:ok, _user} ->
          conn
          |> sudomode(:enable)
          |> put_flash(:info, "Sudo mode is now active.")
          |> redirect(to: path)

        {:error, reason} ->
          conn
          |> put_flash(:error, auth_error_message(:sudo, reason))
          |> put_status(400)
          |> render_sudo
      end
    else
      redirect(conn, to: login_path(conn, :show))
    end
  end

  def delete(conn, _params) do
    destroy_session(conn, return: page_path(Hexpm.Web.Endpoint, :index))
  end

  defp expire_session(conn) do
    path = login_path(conn, :show, return: conn.params["return"]) # pass return parameter

    conn
    |> put_flash(:error, auth_error_message(:expired))
    |> destroy_session(return: path)
  end

  defp destroy_session(conn, [return: return]) do
    conn
    |> delete_session("user_id")
    |> delete_session("sudo")
    |> delete_session("halfopen")
    |> redirect(to: return)
  end

  defp set_last_otp(conn, user, code) do
    case Users.use_twofactor_code(user, code, audit: audit_data(conn)) do
      {:ok, _user} -> :ok
      {:error, _changeset} -> :error
    end
  end

  defp use_backup_code(conn, user, code) do
    case Users.use_twofactor_backupcode(user, code, audit: audit_data(conn)) do
      {:ok, _user} -> :ok
      {:error, _changeset} -> :error
    end
  end

  defp render_show(conn) do
    render conn, "show.html", [
      title: "Log in",
      container: "container page login",
      return: conn.params["return"]
    ]
  end

  defp render_sudo(conn) do
    render conn, "sudo.html", [
      title: "Sudo mode",
      container: "container page login",
      return: conn.params["return"]
    ]
  end

  defp render_show_twofactor_totp(conn) do
    render conn, "twofactor_totp.html", [
      title: "Log in - 2FA",
      container: "container page login",
      return: conn.params["return"]
    ]
  end
end
