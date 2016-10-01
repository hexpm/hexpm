defmodule HexWeb.PasswordResetController do
  use HexWeb.Web, :controller

  def show(conn, _params) do
    render conn, "show.html", [
      title: "Reset your password",
      container: "container page password-view"
    ]
  end

  def create(conn, %{"username" => name}) do
    Users.request_reset(name)

    render conn, "create.html", [
      title: "Reset your password",
      container: "container page password-view"
    ]
  end
end
