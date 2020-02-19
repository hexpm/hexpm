defmodule HexpmWeb.Dashboard.KeyController do
  use HexpmWeb, :controller

  plug :requires_login

  def index(conn, _params) do
    render_index(conn)
  end

  def delete(conn, %{"name" => name}) do
    user = conn.assigns.current_user

    case Keys.revoke(user, name, audit: audit_data(conn)) do
      {:ok, _struct} ->
        conn
        |> put_flash(:info, "The key #{name} was revoked successfully.")
        |> redirect(to: Routes.key_path(conn, :index))

      {:error, _} ->
        conn
        |> put_status(400)
        |> put_flash(:error, "The key #{name} was not found.")
        |> render_index()
    end
  end

  def create(conn, params) do
    user = conn.assigns.current_user
    key_params = munge_permissions(params["key"])

    case Keys.create(user, key_params, audit: audit_data(conn)) do
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
    organizations = Organizations.all_by_user(user)

    render(
      conn,
      "index.html",
      title: "Dashboard - User keys",
      container: "container page dashboard",
      keys: keys,
      organizations: organizations,
      delete_key_path: Routes.key_path(Endpoint, :delete),
      create_key_path: Routes.key_path(Endpoint, :create),
      key_changeset: changeset
    )
  end

  defp changeset() do
    Key.changeset(%Key{}, %{}, %{})
  end

  def munge_permissions(params) do
    permissions = params["permissions"] || []

    permissions =
      if {"repositories", "on"} in permissions do
        Enum.reject(permissions, &match?({"repository", _}, &1))
      else
        permissions
      end

    permissions =
      if {"apis", "on"} in permissions do
        Enum.reject(permissions, &match?({"api", _}, &1))
      else
        permissions
      end

    permissions =
      Enum.flat_map(permissions, fn
        {"repositories", "on"} ->
          [%{"domain" => "repositories", "resource" => nil}]

        {"apis", "on"} ->
          [%{"domain" => "api", "resource" => nil}]

        {"api", resources} ->
          Enum.map(Map.keys(resources), &%{"domain" => "api", "resource" => &1})

        {"repository", resources} ->
          Enum.map(Map.keys(resources), &%{"domain" => "repository", "resource" => &1})
      end)

    put_in(params["permissions"], permissions)
  end
end
