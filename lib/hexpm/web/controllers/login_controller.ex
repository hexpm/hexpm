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

  def create(conn, %{"username" => username, "password" => password, "twofactor"=> otp}) do
    case password_auth(username, password) do
      {:ok, user} ->
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
      {:error, reason} ->
        conn
        |> put_flash(:error, auth_error_message(reason))
        |> put_status(400)
        |> render_show
    end
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
    case Users.use_twofactor_backupcode(user, code, audit: {user, conn.assigns.user_agent}) do
      {:ok, _user} -> :ok
      {:error, _changeset} -> :error
    end
  end

  def delete(conn, _params) do
    conn
    |> delete_session("username")
    |> redirect(to: page_path(Hexpm.Web.Endpoint, :index))
  end

  defp render_show(conn) do
    render conn, "show.html", [
      title: "Log in",
      container: "container page login",
      return: conn.params["return"]
    ]
  end
end
