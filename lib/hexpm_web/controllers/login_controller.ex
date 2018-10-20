defmodule HexpmWeb.LoginController do
  use HexpmWeb, :controller

  plug :nillify_params, ["return"]

  def show(conn, _params) do
    if logged_in?(conn) do
      redirect_return(conn, conn.assigns.current_user)
    else
      render_show(conn)
    end
  end

  def create(conn, %{"username" => username, "password" => password}) do
    case password_auth(username, password) do
      {:ok, user} ->
        conn
        |> configure_session(renew: true)
        |> put_session("user_id", user.id)
        |> redirect_return(user)

      {:error, reason} ->
        conn
        |> put_flash(:error, auth_error_message(reason))
        |> put_status(400)
        |> render_show()
    end
  end

  def delete(conn, _params) do
    conn
    |> delete_session("user_id")
    |> redirect(to: Routes.page_path(HexpmWeb.Endpoint, :index))
  end

  defp redirect_return(%{params: %{"hexdocs" => organization}} = conn, user) do
    case generate_hexdocs_key(user, organization) do
      {:ok, key} ->
        docs_url =
          Application.get_env(:hexpm, :docs_url)
          |> String.replace("://", "://#{organization}.")

        url = "#{docs_url}#{conn.params["return"]}?key=#{key.user_secret}"
        redirect(conn, external: url)

      {:error, _changeset} ->
        conn
        |> put_flash(:error, "You don't have access to organization #{organization}")
        |> put_status(400)
        |> render_show()
    end
  end

  defp redirect_return(conn, user) do
    path = conn.params["return"] || Routes.user_path(conn, :show, user)
    redirect(conn, to: path)
  end

  defp generate_hexdocs_key(user, organization) do
    Keys.create_for_docs(user, organization)
  end

  defp render_show(conn) do
    render(
      conn,
      "show.html",
      title: "Log in",
      container: "container page page-xs login",
      return: conn.params["return"],
      hexdocs: conn.params["hexdocs"]
    )
  end
end
