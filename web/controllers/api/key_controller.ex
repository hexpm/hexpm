defmodule HexWeb.API.KeyController do
  use HexWeb.Web, :controller

  plug :authorize when action != :create
  plug :authorize, [only_basic: true, allow_unconfirmed: true] when action == :create

  def index(conn, _params) do
    user = conn.assigns.user
    authing_key = conn.assigns.key

    keys = Key.all(user) |> HexWeb.Repo.all

    conn
    |> api_cache(:private)
    |> render(:index, keys: keys, authing_key: authing_key)
  end

  def show(conn, %{"name" => name}) do
    user = conn.assigns.user
    authing_key = conn.assigns.key

    key = HexWeb.Repo.one!(Key.get(name, user))

    when_stale(conn, key, fn conn ->
      conn
      |> api_cache(:private)
      |> render(:show, key: key, authing_key: authing_key)
    end)
  end

  def create(conn, params) do
    user = conn.assigns.user
    authing_key = conn.assigns.key

    multi =
      Ecto.Multi.new
      |> Ecto.Multi.insert(:key, Key.build(user, params))
      |> audit(conn, "key.generate", fn %{key: key} -> key end)

    case HexWeb.Repo.transaction(multi) do
      {:ok, %{key: key}} ->
        location = key_url(conn, :show, params["name"])

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

    if key = HexWeb.Repo.one(Key.get(name, user)) do
      Ecto.Multi.new
      |> Ecto.Multi.update(:key, Key.revoke(key))
      |> audit(conn, "key.remove", key)
      |> HexWeb.Repo.transaction
      |> case do
        {:ok, %{key: key}} ->
          conn
          |> api_cache(:private)
          |> put_status(200)
          |> render(:delete, key: key, authing_key: authing_key)
        _ ->
          not_found(conn)
      end
    else
      not_found(conn)
    end
  end

  def delete_all(conn, _params) do
    user = conn.assigns.user
    key = conn.assigns.key

    {:ok, _} =
      Ecto.Multi.new
      |> Ecto.Multi.update_all(:keys, Key.revoke_all(user), [])
      |> audit_many(conn, "key.remove", Key.all(user) |> HexWeb.Repo.all)
      |> HexWeb.Repo.transaction

    conn
    |> put_status(200)
    |> render(:delete, key: HexWeb.Repo.get!(Key, key.id), authing_key: key)
  end
end
