defmodule Hexpm.Web.EmailController do
  use Hexpm.Web, :controller

  def verify(conn, %{"username" => username, "email" => email, "key" => key}) do
    success = Users.verify_email(username, email, key) == :ok
    conn =
      if success do
        put_flash(conn, :info, "Your email #{email} has been verified.")
      else
        put_flash(conn, :error, "Your email #{email} failed to verify.")
      end

    conn
    |> put_flash(:custom_location, true)
    |> redirect(to: Routes.page_path(Hexpm.Web.Endpoint, :index))
  end
end
