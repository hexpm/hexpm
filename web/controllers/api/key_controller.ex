defmodule HexWeb.API.KeyController do
  use HexWeb.Web, :controller

  plug :authorize when action != :create
  plug :authorize, [only_basic: true, allow_unconfirmed: true] when action == :create

  def index(conn, _params) do
    keys = Key.all(conn.assigns.user) |> HexWeb.Repo.all

    conn
    |> api_cache(:private)
    |> render(:index, keys: keys)
  end

  def show(conn, %{"name" => name}) do
    key = HexWeb.Repo.one!(Key.get(name, conn.assigns.user))

    when_stale(conn, key, fn conn ->
      conn
      |> api_cache(:private)
      |> render(:show, key: key)
    end)
  end

  def create(conn, params) do
    user = conn.assigns.user

    multi =
      Ecto.Multi.new
      |> Ecto.Multi.insert(:key, Key.build(user, params))
      |> audit(user, "key.generate", fn %{key: key} -> key end)

    case HexWeb.Repo.transaction(multi) do
      {:ok, %{key: key}} ->
        location = key_url(conn, :show, params["name"])

        conn
        |> put_resp_header("location", location)
        |> api_cache(:private)
        |> put_status(201)
        |> render(:show, key: key)
      {:error, :key, changeset, _} ->
        validation_failed(conn, changeset)
    end
  end

  def delete(conn, %{"name" => name}) do
    user = conn.assigns.user

    if key = HexWeb.Repo.one(Key.get(name, user)) do
      Ecto.Multi.new
      |> Ecto.Multi.update_all(:key, Key.revoke(user, name), [])
      |> audit(conn, "key.remove", key)
      |> HexWeb.Repo.transaction
      |> case do
        {:ok, _} ->
          if key.id === user.current_key_id do
            key = HexWeb.Repo.get!(assoc(user, :keys), key.id)
            conn
            |> api_cache(:private)
            |> put_status(200)
            |> render(:delete, key: key)
          else
            conn
            |> api_cache(:private)
            |> send_resp(204, "")
          end
        _ ->
          not_found(conn)
      end
    else
      not_found(conn)
    end
  end

  def delete_all(conn, _params) do
    user = conn.assigns.user

    keys = Key.all(user) |> HexWeb.Repo.all
    key = Enum.find(keys, fn (key) ->
      key.id === user.current_key_id
    end)

    audit_fields = HexWeb.AuditLog.__schema__(:fields) -- [:id]
    audit_extra = %{inserted_at: Ecto.DateTime.utc}
    audit_key_remove = fn (key) ->
      conn
      |> audit("key.remove", key)
      |> Ecto.Changeset.apply_changes()
      |> Map.take(audit_fields)
      |> Map.merge(audit_extra)
    end

    {:ok, _} =
      Ecto.Multi.new
      |> Ecto.Multi.update_all(:keys, Key.revoke_all(user), [])
      |> Ecto.Multi.insert_all(:log, HexWeb.AuditLog, Enum.map(keys, audit_key_remove))
      |> HexWeb.Repo.transaction

    if key do
      key = HexWeb.Repo.get!(assoc(conn.assigns.user, :keys), key.id)
      conn
      |> put_status(200)
      |> render(:delete, key: key)
    else
      conn
      |> send_resp(204, "")
    end
  end
end
