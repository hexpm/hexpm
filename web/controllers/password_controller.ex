defmodule HexWeb.PasswordController do
  use HexWeb.Web, :controller

  def show_confirm(conn, %{"username" => username, "key" => key}) do
    user = HexWeb.Repo.get_by(User, username: username)
    success = User.confirm?(user, key)

    if success do
      User.confirm(user) |> HexWeb.Repo.update!
      User.send_confirmed_email(user)
    end

    render conn, "confirm.html", [
      success: success
    ]
  end

  def show_reset(conn, %{"username" => username, "key" => key}) do
    render conn, "reset.html", [
      username: username,
      key: key
    ]
  end

  def reset(conn, %{"username" => username, "key" => key, "password" => password}) do
    user = HexWeb.Repo.get_by(User, username: username)
    success = User.reset?(user, key)

    if success do
      User.reset(user, password)
      User.send_reset_email(user)
    end

    render conn, "reset_result.html", [
      success: success
    ]
  end
end
