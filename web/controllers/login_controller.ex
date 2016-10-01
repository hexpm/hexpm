defmodule HexWeb.LoginController do
  use HexWeb.Web, :controller

  def show(conn, _params) do
    render conn, "login.html", [
      title: "Log in",
      container: "container page login-view"
    ]
  end
end
