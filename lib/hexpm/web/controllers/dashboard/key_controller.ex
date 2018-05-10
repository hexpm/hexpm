defmodule Hexpm.Web.Dashboard.KeyController do
  use Hexpm.Web, :controller

  plug :requires_login

  def index(conn, _params) do
    user = conn.assigns.current_user
    keys = Keys.all(user)

    render_index(conn, keys)
  end

  def delete(conn, %{"name" => name} = params) do
    user = conn.assigns.current_user

    case Keys.remove(user, name, audit: audit_data(conn)) do
      {:ok, _struct} ->
        conn
        |> put_flash(:info, "The key #{params["name"]} was revoked successfully.")
        |> redirect(to: Routes.key_path(conn, :index))

      {:error, _} ->
        conn
        |> put_status(400)
        |> put_flash(:error, "The key #{params["name"]} was not found.")
        |> render_index(Keys.all(user))
    end
  end

  def create(conn, %{"key" => %{"name" => _}} = params) do
    user = conn.assigns.current_user

    case Keys.add(user, params["key"], audit: audit_data(conn)) do
      {:ok, %{key: key}} ->
        flash =
          "The key #{key.name} was successfully generated, " <>
            "copy the secret \"#{key.user_secret}\", you won't be able to see it again."

        conn
        |> put_flash(:info, flash)
        |> redirect(to: Routes.key_path(conn, :index))

      {:error, :key, changeset, _} ->
        conn
        |> put_status(400)
        |> render_index(Keys.all(user), changeset)
    end
  end

  defp render_index(conn, keys, changeset \\ changeset()) do
    render(
      conn,
      "index.html",
      title: "Dashboard - User keys",
      container: "container page dashboard",
      keys: keys,
      changeset: changeset
    )
  end

  defp changeset do
    Key.changeset(%Key{}, %{}, %{})
  end
end
