defmodule HexpmWeb.PasswordResetController do
  use HexpmWeb, :controller

  def show(conn, _params) do
    render_show(conn)
  end

  def create(conn, %{"username" => name} = params) do
    if HexpmWeb.Captcha.verify(params["h-captcha-response"]) do
      Users.password_reset_init(name, audit: audit_data(conn))

      render(
        conn,
        "create.html",
        title: "Reset your password",
        container: "container page page-xs password-view"
      )
    else
      conn
      |> put_status(400)
      |> put_flash(:error, "Oops, something went wrong!")
      |> render_show("Please complete the captcha to reset password")
    end
  end

  defp render_show(conn, captcha_error \\ nil) do
    render(
      conn,
      "show.html",
      title: "Reset your password",
      container: "container page page-xs password-view",
      captcha_error: captcha_error
    )
  end
end
