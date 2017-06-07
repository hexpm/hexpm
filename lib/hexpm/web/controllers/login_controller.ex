defmodule Hexpm.Web.LoginController do
  use Hexpm.Web, :controller

  plug :nillify_params, ["return"]

  def show(conn, _params) do
    if logged_in?(conn) do
      username = get_session(conn, "username")
      path = conn.params["return"] || user_path(conn, :show, username)
      redirect(conn, to: path)
    else
      render_show(conn)
    end
  end

  def show_twofactor_totp(conn, params) do
    should_be_here? = true #TODO

    if should_be_here? do
      render_show_twofactor_totp(conn)
    else
      path = login_path(conn, :show)
      redirect(conn, to: path)
    end
  end

  def create(conn, %{"username" => username, "password" => password}) do
    case password_auth(username, password) do
      {:ok, user} ->
        if user.twofactor.enabled do
          # take user to 2FA
        else
          create_session(conn, user)
        end
      {:error, reason} ->
        conn
        |> put_flash(:error, auth_error_message(reason))
        |> put_status(400)
        |> render_show
    end
  end

  def create_twofactor_totp(conn, %{"otp" => otp}) do
    user = nil
    case Auth.twofactor_auth(user, otp) do
        {:ok, user} ->
          create_session(conn, user)

        {:backupcode, user, code} ->
          case use_backup_code(conn, user, code) do
            :ok ->
              create_session(conn, user)
            :error ->
              conn
              |> put_flash(:error, auth_error_message(:twofactor))
              |> put_status(400)
              |> render_show
          end

        :error ->
          conn
          |> put_flash(:error, auth_error_message(:twofactor))
          |> put_status(400)
          |> render_show
    end
  end

  def delete(conn, _params) do
    conn
    |> delete_session("username")
    |> redirect(to: page_path(Hexpm.Web.Endpoint, :index))
  end

  defp create_session(conn, user) do
    user = Users.sign_in(user)
    path = conn.params["return"] || user_path(conn, :show, user)

    conn
    |> put_session("username", user.username)
    |> put_session("key", user.session_key)
    |> redirect(to: path)
  end

  defp use_backup_code(conn, user, code) do
    # audit_data(conn) is not used because the session is technically
    # not active yet
    audit_data = {user, conn.assigns.user_agent}

    case Users.use_twofactor_backupcode(user, code, audit: audit_data) do
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

  defp render_show_twofactor_totp(conn) do
    render conn, "twofactor_totp.html", [
      title: "Log in - 2FA",
      container: "container page login",
      return: conn.params["return"]
    ]
  end
end
