defmodule Hexpm.Web.API.KeyController do
  use Hexpm.Web, :controller

  plug :authorize,
       [domain: "api", resource: "write", allow_unconfirmed: true]
       when action == :create

  plug :authorize, [domain: "api", resource: "write"] when action in [:delete, :delete_all]
  plug :authorize, [domain: "api", resource: "read"] when action in [:index, :show]

  # TODO: Add filtering on domain and resource
  def index(conn, _params) do
    user = conn.assigns.current_user
    authing_key = conn.assigns.key
    keys = Keys.all(user)

    conn
    |> api_cache(:private)
    |> render(:index, keys: keys, authing_key: authing_key)
  end

  def show(conn, %{"name" => name}) do
    user = conn.assigns.current_user
    authing_key = conn.assigns.key
    key = Keys.get(user, name)

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
    user = conn.assigns.current_user
    authing_key = conn.assigns.key

    if api_key?(params) and conn.assigns.auth_source == :key do
      Hexpm.Web.AuthHelpers.error(conn, {:error, :basic_required})
    else
      case Keys.add(user, params, audit: audit_data(conn)) do
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
  end

  defp api_key?(params) do
    params["permissions"] in [nil, []] or
      Enum.any?(params["permissions"], fn permission ->
        permission["domain"] == "api"
      end)
  end

  def delete(conn, %{"name" => name}) do
    user = conn.assigns.current_user
    authing_key = conn.assigns.key

    case Keys.remove(user, name, audit: audit_data(conn)) do
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
    user = conn.assigns.current_user
    key = conn.assigns.key
    {:ok, _} = Keys.remove_all(user, audit: audit_data(conn))

    conn
    |> put_status(200)
    |> render(:delete, key: Keys.get(key.id), authing_key: key)
  end
end
