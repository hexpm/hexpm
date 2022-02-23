defmodule HexpmWeb.API.KeyController do
  use HexpmWeb, :controller

  plug :fetch_organization

  plug :authorize,
       [
         domain: "api",
         resource: "write",
         allow_unconfirmed: true,
         fun: &organization_access/3,
         opts: [organization_role: "write"]
       ]
       when action == :create

  plug :authorize,
       [
         domain: "api",
         resource: "write",
         fun: &organization_access/3,
         authentication: :required,
         opts: [organization_role: "write"]
       ]
       when action in [:delete, :delete_all]

  plug :authorize,
       [domain: "api", resource: "read", authentication: :required, fun: &organization_access/2]
       when action in [:index, :show]

  plug :require_organization_path

  def index(conn, _params) do
    user_or_organization = conn.assigns.organization || conn.assigns.current_user
    authing_key = conn.assigns.key
    keys = Keys.all(user_or_organization)

    conn
    |> api_cache(:private)
    |> render(:index, keys: keys, authing_key: authing_key)
  end

  def show(conn, %{"name" => name}) do
    user_or_organization = conn.assigns.organization || conn.assigns.current_user
    authing_key = conn.assigns.key
    key = Keys.get(user_or_organization, name)

    if key do
      when_stale(conn, key, fn conn ->
        conn
        |> api_cache(:private)
        |> render(:show, key: key, authing_key: authing_key)
      end)
    else
      not_found(conn)
    end
  end

  def create(conn, params) do
    user_or_organization = conn.assigns.organization || conn.assigns.current_user
    authing_key = conn.assigns.key

    case Keys.create(user_or_organization, params, audit: audit_data(conn)) do
      {:ok, %{key: key}} ->
        location = Routes.api_key_url(conn, :show, params["name"])

        conn
        |> put_resp_header("location", location)
        |> api_cache(:private)
        |> put_status(201)
        |> render(:show, key: key, authing_key: authing_key)

      {:error, :key, changeset, _} ->
        validation_failed(conn, changeset)
    end
  end

  def delete(conn, %{"name" => name}) do
    user_or_organization = conn.assigns.organization || conn.assigns.current_user
    authing_key = conn.assigns.key

    case Keys.revoke(user_or_organization, name, audit: audit_data(conn)) do
      {:ok, %{key: key}} ->
        conn
        |> api_cache(:private)
        |> put_status(200)
        |> render(:delete, key: key, authing_key: authing_key)

      _ ->
        not_found(conn)
    end
  end

  def delete_all(conn, _params) do
    user_or_organization = conn.assigns.organization || conn.assigns.current_user
    key = conn.assigns.key
    {:ok, _} = Keys.revoke_all(user_or_organization, audit: audit_data(conn))

    conn
    |> put_status(200)
    |> render(:delete, key: Keys.get(key.id), authing_key: key)
  end

  defp require_organization_path(conn, _opts) do
    if conn.assigns.current_organization && !conn.assigns.organization do
      not_found(conn)
    else
      conn
    end
  end
end
