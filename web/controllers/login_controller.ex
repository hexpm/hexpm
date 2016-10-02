defmodule HexWeb.LoginController do
  use HexWeb.Web, :controller

  def show(conn, _params) do
    if get_session(conn, "username") do
      redirect(conn, to: "/") # TODO: user_path(conn, :show, username)
    else
      render_show(conn)
    end
  end

  def create(conn, %{"username" => username, "password" => password}) do
    case auth(username, password) do
      {:ok, _user} ->
        conn
        |> put_session("username", username)
        |> redirect(to: "/") # TODO: user_path(conn, :show, username)
      {:error, reason} ->
        conn
        |> put_flash(:error, error_to_message(reason))
        |> put_status(400)
        |> render_show
    end
  end

  def delete(conn, _params) do
    conn
    |> delete_session("username")
    |> redirect(to: "/")
  end

  defp auth(username, password) do
    case HexWeb.Auth.password_auth(username, password) do
      {:ok, {user, nil}} ->
        if user.confirmed,
          do: {:ok, user},
        else: {:error, :unconfirmed}
      :error ->
        {:error, :wrong}
    end
  end

  defp render_show(conn) do
    render conn, "show.html", [
      title: "Log in",
      container: "container page login-view"
    ]
  end

  defp error_to_message(:wrong), do: "Invalid username, email or password"
  defp error_to_message(:unconfirmed), do: "Email has not been confirmed yet"
end
