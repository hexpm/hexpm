defmodule HexWeb.API.UserController do
  use HexWeb.Web, :controller

  def create(conn, params) do
    # Unconfirmed users can be recreated
    if (user = User.get(username: params["username"])) && not user.confirmed do
      User.delete(user)
    end

    case User.create(params) do
      {:ok, user} ->
        location = user_url(conn, :show, params["username"])

        conn
        |> put_resp_header("location", location)
        |> api_cache(:private)
        |> put_status(201)
        |> render(:show, user: user)
      {:error, errors} ->
        validation_failed(conn, errors)
    end
  end

  def show(conn, %{"name" => name}) do
     authorized(conn, [], &(&1.username == name), fn user ->
      user = HexWeb.Repo.preload(user, :owned_packages)

      when_stale(conn, user, fn conn ->
        conn
        |> api_cache(:private)
        |> render(:show, user: user)
      end)
    end)
  end

  def reset(conn, %{"name" => name}) do
    if (user = User.get(username: name) || User.get(email: name)) do
      User.password_reset(user)

      conn
      |> api_cache(:private)
      |> send_resp(204, "")
    else
      not_found(conn)
    end
  end
end
