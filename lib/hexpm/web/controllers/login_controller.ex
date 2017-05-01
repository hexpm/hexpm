defmodule Hexpm.Web.LoginController do
  use Hexpm.Web, :controller

  plug :nillify_params, ["return"]

  def show(conn, _params) do
    if logged_in?(conn) do
      path = conn.params["return"] || user_path(conn, :show, conn.assigns.logged_in)
      redirect(conn, to: path)
    else
      render_show(conn)
    end
  end

  def create(conn, %{"username" => username, "password" => password}) do
    case password_auth(username, password) do
      {:ok, user} ->
        path = conn.params["return"] || user_path(conn, :show, user)

        conn
        |> configure_session(renew: true)
        |> put_session("user_id", user.id)
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
    |> delete_session("user_id")
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
