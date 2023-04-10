defmodule HexpmWeb.SignupController do
  use HexpmWeb, :controller

  def show(conn, _params) do
    if logged_in?(conn) do
      path = ~p"/users/#{conn.assigns.current_user}"
      redirect(conn, to: path)
    else
      render_show(conn, User.build(%{}))
    end
  end

  def create(conn, params) do
    if HexpmWeb.Captcha.verify(params["h-captcha-response"]) do
      case Users.add(params["user"], audit: audit_data(conn)) do
        {:ok, _user} ->
          flash =
            "A confirmation email has been sent, " <>
              "you will have access to your account shortly."

          conn
          |> put_flash(:info, flash)
          |> redirect(to: ~p"/")

        {:error, changeset} ->
          conn
          |> put_status(400)
          |> render_show(changeset)
      end
    else
      changeset = %{User.build(params["user"]) | action: :insert}

      conn
      |> put_status(400)
      |> render_show(changeset, "Please complete the captcha to sign up")
    end
  end

  defp render_show(conn, changeset, captcha_error \\ nil) do
    render(
      conn,
      "show.html",
      title: "Sign up",
      container: "container page page-xs signup",
      changeset: changeset,
      captcha_error: captcha_error
    )
  end
end
