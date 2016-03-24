defmodule HexWeb.API.UserController do
  use HexWeb.Web, :controller

  plug :authorize, [fun: &correct_user?/2] when action == :show

  def create(conn, params) do
    # Unconfirmed users can be recreated
    if (user = HexWeb.Repo.get_by(User, username: params["username"])) && !user.confirmed do
      # Unconfirmed users only have the key creation in the audits log
      # That key will be deleted when the user is deleted
      HexWeb.Repo.delete_all(assoc(user, :audit_logs))
      HexWeb.Repo.delete!(user)
    end

    case User.create(params) |> HexWeb.Repo.insert do
      {:ok, user} ->
        HexWeb.Mailer.send(
          "confirmation_request.html",
          "Hex.pm - Account confirmation",
          [user.email],
          username: user.username,
          key: user.confirmation_key)

        location = user_url(conn, :show, user.username)

        conn
        |> put_resp_header("location", location)
        |> api_cache(:private)
        |> put_status(201)
        |> render(:show, user: user)
      {:error, changeset} ->
        validation_failed(conn, changeset)
    end
  end

  def show(conn, _params) do
    user = HexWeb.Repo.preload(conn.assigns.user, :owned_packages)

    when_stale(conn, user, fn conn ->
      conn
      |> api_cache(:private)
      |> render(:show, user: user)
    end)
  end

  def reset(conn, %{"name" => name}) do
    user = HexWeb.Repo.get_by(User, username: name) ||
             HexWeb.Repo.get_by(User, email: name)

    if user do
      user = User.password_reset(user) |> HexWeb.Repo.update!

      HexWeb.Mailer.send(
        "password_reset_request.html",
        "Hex.pm - Password reset request",
        [user.email],
        username: user.username,
        key: user.reset_key)

      conn
      |> api_cache(:private)
      |> send_resp(204, "")
    else
      not_found(conn)
    end
  end
end
