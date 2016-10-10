defmodule HexWeb.EmailController do
  use HexWeb.Web, :controller

  def confirm(conn, %{"username" => username, "key" => key}) do
    success = Users.confirm(username, key) == :ok
    title = if success, do: "Email confirmed", else: "Failed to confirm email"

    conn
    |> put_status(success_to_status(success))
    |> render("confirm.html", [
      title: title,
      success: success
    ])
  end
end
