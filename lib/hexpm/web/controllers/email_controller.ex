defmodule Hexpm.Web.EmailController do
  use Hexpm.Web, :controller

  # TODO: Sign in user after verification

  def verify(conn, %{"username" => username, "email" => email, "key" => key}) do
    success = Users.verify_email(username, email, key) == :ok
    conn =
      if success,
        do: put_flash(conn, :info, "Your email #{email} has been verified."),
      else: put_flash(conn, :error, "Your email #{email} failed to verify.")

    conn
    |> put_flash(:custom_location, true)
    |> redirect(to: page_path(Hexpm.Web.Endpoint, :index))
  end
end
