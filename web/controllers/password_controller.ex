defmodule HexWeb.PasswordController do
  use HexWeb.Web, :controller

  def show_confirm(conn, %{"username" => username, "key" => key}) do
    user = HexWeb.Repo.get_by(User, username: username)
    success = User.confirm?(user, key)

    if success do
      User.confirm(user) |> HexWeb.Repo.update!
      HexWeb.Mailer.send("confirmed.html", "Hex.pm - Account confirmed", [user.email], [])
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
      HexWeb.Mailer.send("password_reset.html", "Hex.pm - Password reset", [user.email], [])
    end

    render conn, "reset_result.html", [
      success: success
    ]
  end
end
