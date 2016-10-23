defmodule HexWeb.SignupController do
  use HexWeb.Web, :controller

  def show(conn, _params) do
    render_show(conn, User.build(%{}))
  end

  def create(conn, params) do
    case Users.add(params["user"], audit: audit_data(conn)) do
      {:ok, _user} ->
        conn
        |> put_flash(:info, "A confirmation email has been sent, you will have access to your account shortly.")
        |> put_flash(:custom_location, true)
        |> redirect(to: "/")
      {:error, changeset} ->
        conn
        |> put_status(400)
        |> render_show(changeset)
    end
  end

  defp render_show(conn, changeset) do
    render conn, "show.html", [
      title: "Sign up",
      container: "container page signup",
      changeset: changeset
    ]
  end
end
