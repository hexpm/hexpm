defmodule HexWeb.PasswordController do
  use HexWeb.Web, :controller

  def show_confirm(conn, params) do
    render conn, "confirm.html", [
      success: User.confirm?(params["username"], params["key"])
    ]
  end

  def show_reset(conn, params) do
    render conn, "reset.html", [
      username: params["username"],
      key: params["key"]
    ]
  end

  def reset(conn, params) do
    render conn, "reset_result.html", [
      success: User.reset?(params["username"], params["key"], params["password"])
    ]
  end
end
