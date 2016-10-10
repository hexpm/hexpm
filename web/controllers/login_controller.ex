defmodule HexWeb.LoginController do
  use HexWeb.Web, :controller

  def show(conn, _params) do
    if username = get_session(conn, "username") do
      path = conn.params["return"] || user_path(conn, :show, username)
      redirect(conn, to: path)
    else
      render_show(conn)
    end
  end

  def create(conn, %{"username" => username, "password" => password}) do
    case password_auth(username, password) do
      {:ok, user} ->
        path = conn.params["return"] || user_path(conn, :show, user.username)

        conn
        |> put_session("username", user.username)
        |> put_session("email", user.email)
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
