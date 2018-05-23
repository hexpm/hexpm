defmodule Hexpm.Web.Dashboard.KeyController do
  use Hexpm.Web, :controller

  plug :requires_login

  def index(conn, _params) do
    render_index(conn)
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
        |> render_index()
    end
  end

  def create(conn, params) do
    user = conn.assigns.current_user
    key_params = fixup_permissions(params["key"])

    case Keys.add(user, key_params, audit: audit_data(conn)) do
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
        |> render_index(changeset)
    end
  end

  defp render_index(conn, changeset \\ changeset()) do
    user = conn.assigns.current_user
    keys = Keys.all(user)
    repositories = Repositories.all_by_user(user)

    render(
      conn,
      "index.html",
      title: "Dashboard - User keys",
      container: "container page dashboard",
      keys: keys,
      repositories: repositories,
      changeset: changeset
    )
  end

  defp changeset do
    Key.changeset(%Key{}, %{}, %{})
  end

  defp fixup_permissions(params) do
    update_in(params["permissions"], fn permissions ->
      Map.new(permissions || [], fn {index, permission} ->
        if permission["domain"] == "repository" and permission["resource"] == "All" do
          {index, %{permission | "domain" => "repositories", "resource" => nil}}
        else
          {index, permission}
        end
      end)
    end)
  end
end
