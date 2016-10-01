defmodule HexWeb.SignupController do
  use HexWeb.Web, :controller

  def signup(conn, _params) do
    render conn, "signup.html", [
      title: "Sign up",
      container: "container page login-view"
    ]
  end

  def confirm(conn, %{"username" => username, "key" => key}) do
    success = Users.confirm(username, key) == :ok
    title = if success, do: "Email confirmed", else: "Failed to confirm email"

    render conn, "confirm.html", [
      title: title,
      success: success
    ]
  end
end
