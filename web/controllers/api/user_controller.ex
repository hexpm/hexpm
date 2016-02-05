defmodule HexWeb.API.UserController do
  use HexWeb.Web, :controller

  def create(conn, %{"username" => username} = params) do
    # Unconfirmed users can be recreated
    if (user = HexWeb.Repo.get_by(User, username: username)) &&
       not user.confirmed do
      HexWeb.Repo.delete!(user)
    end

    case User.create(params) |> HexWeb.Repo.insert do
      {:ok, user} ->
        HexWeb.Mailer.send(
          "confirmation_request.html",
          "Hex.pm - Account confirmation",
          user.email,
          username: user.username,
          key: user.confirmation_key)

        location = user_url(conn, :show, username)

        conn
        |> put_resp_header("location", location)
        |> api_cache(:private)
        |> put_status(201)
        |> render(:show, user: user)
      {:error, changeset} ->
        validation_failed(conn, changeset.errors)
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
    if (user = HexWeb.Repo.get_by!(User, username: name) ||
       HexWeb.Repo.get_by!(User, email: name)) do
      user = User.password_reset(user) |> HexWeb.Repo.update!

      HexWeb.Mailer.send(
        "password_reset_request.html",
        "Hex.pm - Password reset request",
        user.email,
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
