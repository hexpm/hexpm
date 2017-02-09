defmodule HexWeb.API.KeyController do
  use HexWeb.Web, :controller

  plug :authorize when action != :create
  plug :authorize, [only_basic: true, allow_unconfirmed: true] when action == :create

  def index(conn, _params) do
    user = conn.assigns.user
    authing_key = conn.assigns.key

    keys = Keys.all(user)

    conn
    |> api_cache(:private)
    |> render(:index, keys: keys, authing_key: authing_key)
  end

  def show(conn, %{"name" => name}) do
    user = conn.assigns.user
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
    user = conn.assigns.user
    authing_key = conn.assigns.key

    case Keys.add(user, params, audit: audit_data(conn)) do
      {:ok, %{key: key}} ->
        location = api_key_url(conn, :show, params["name"])

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
    user = conn.assigns.user
    authing_key = conn.assigns.key

    case Keys.remove(user, name, [audit: audit_data(conn)]) do
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
    user = conn.assigns.user
    key = conn.assigns.key

    {:ok, _} = Keys.remove_all(user, audit: audit_data(conn))

    conn
    |> put_status(200)
    |> render(:delete, key: Keys.get(key.id), authing_key: key)
  end
end
