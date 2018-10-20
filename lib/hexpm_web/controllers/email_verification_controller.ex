defmodule HexpmWeb.EmailVerificationController do
  use HexpmWeb, :controller

  def verify(conn, %{"username" => username, "email" => email, "key" => key}) do
    success = Users.verify_email(username, email, key) == :ok

    conn =
      if success do
        put_flash(conn, :info, "Your email #{email} has been verified.")
      else
        put_flash(conn, :error, "Your email #{email} failed to verify.")
      end

    redirect(conn, to: Routes.page_path(HexpmWeb.Endpoint, :index))
  end

  def show(conn, _params) do
    render(
      conn,
      "show.html",
      title: "Verify email",
      container: "container page page-xs"
    )
  end

  def create(conn, %{"email" => email_address}) do
    if email = Users.get_email(email_address, [:user]) do
      unless email.verified do
        Users.email_verification(email.user, email)
      end
    end

    conn
    |> put_flash(:info, "A verification email has been sent to #{email_address}.")
    |> redirect(to: Routes.page_path(HexpmWeb.Endpoint, :index))
  end
end
