defmodule HexWeb.API.KeyController do
  use HexWeb.Web, :controller

  def index(conn, _params) do
    authorized(conn, [], fn user ->
      conn
      |> api_cache(:private)
      |> render(:index, keys: Key.all(user))
    end)
  end

  def show(conn, %{"name" => name}) do
    authorized(conn, [], fn user ->
      if key = Key.get(name, user) do
        when_stale(conn, key, fn conn ->
          conn
          |> api_cache(:private)
          |> render(:show, key: key)
        end)
      else
        not_found(conn)
      end
    end)
  end

  def create(conn, params) do
    auth_opts = [only_basic: true, allow_unconfirmed: true]

    authorized(conn, auth_opts, fn user ->
      case Key.create(user, conn.params) do
        {:ok, key} ->
          location = api_url(["keys", params["name"]])

          conn
          |> put_resp_header("location", location)
          |> api_cache(:private)
          |> put_status(201)
          |> render(:show, key: key)
        {:error, errors} ->
          validation_failed(conn, errors)
      end
    end)
  end

  def delete(conn, %{"name" => name}) do
    authorized(conn, [], fn user ->
      if key = Key.get(name, user) do
        Key.delete(key)

        conn
        |> api_cache(:private)
        |> send_resp(204, "")
      else
        not_found(conn)
      end
    end)
  end
end
