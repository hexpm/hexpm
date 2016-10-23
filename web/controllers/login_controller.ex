defmodule HexWeb.LoginController do
  use HexWeb.Web, :controller

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

  def create(conn, %{"username" => username, "password" => password}) do
    case password_auth(username, password) do
      {:ok, user} ->
        user = Users.sign_in(user)
        path = conn.params["return"] || user_path(conn, :show, user)

        conn
        |> put_session("username", user.username)
        |> put_session("key", user.session_key)
        |> redirect(to: path)
      {:error, reason} ->
        conn
        |> put_flash(:error, auth_error_message(reason))
        |> put_status(400)
        |> render_show
    end
  end

  def delete(conn, _params) do
    conn
    |> delete_session("username")
    |> redirect(to: "/")
  end

  defp render_show(conn) do
    render conn, "show.html", [
      title: "Log in",
      container: "container page login",
      return: conn.params["return"]
    ]
  end
end
