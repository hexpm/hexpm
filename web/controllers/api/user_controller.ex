defmodule HexWeb.API.UserController do
  use HexWeb.Web, :controller

  def create(conn, params) do
    params = email_param(params)

    case Users.add(params) do
      {:ok, user} ->
        location = api_user_url(conn, :show, user.username)

        conn
        |> put_resp_header("location", location)
        |> api_cache(:private)
        |> put_status(201)
        |> render(:show, user: user)
      {:error, changeset} ->
        validation_failed(conn, changeset)
    end
  end

  def show(conn, %{"name" => username}) do
    user =
      username
      |> Users.get
      |> Users.with_owned_packages
      |> Users.with_emails

    when_stale(conn, user, fn conn ->
      conn
      |> api_cache(:private)
      |> render(:show, user: user)
    end)
  end

  def reset(conn, %{"name" => name}) do
    Users.request_reset(name)

    conn
    |> api_cache(:private)
    |> send_resp(204, "")
  end

  defp email_param(params) do
    if email = params["email"] do
      Map.put_new(params, "emails", [%{"email" => email}])
    else
      params
    end
  end
end
