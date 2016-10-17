defmodule HexWeb.EmailController do
  use HexWeb.Web, :controller

  def verify(conn, %{"username" => username, "email" => email, "key" => key}) do
    success = Users.verify_email(username, email, key) == :ok
    title = if success, do: "Email verified", else: "Failed to verify email"

    conn
    |> put_status(success_to_status(success))
    |> render("verify.html", [
      title: title,
      success: success
    ])
  end
end
