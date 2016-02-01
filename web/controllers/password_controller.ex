defmodule HexWeb.PasswordController do
  use HexWeb.Web, :controller

  def show_confirm(conn, %{"username" => username, "key" => key}) do
    render conn, "confirm.html", [
      success: User.confirm?(username, key)
    ]
  end

  def show_reset(conn, %{"username" => username, "key" => key}) do
    render conn, "reset.html", [
      username: username,
      key: key
    ]
  end

  def reset(conn, %{"username" => username, "key" => key, "password" => password}) do
    render conn, "reset_result.html", [
      success: User.reset?(username, key, password)
    ]
  end
end
