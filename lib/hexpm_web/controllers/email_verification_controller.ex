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

    redirect(conn, to: ~p"/")
  end

  def show(conn, _params) do
    render(
      conn,
      "show.html",
      title: "Verify email",
      container: "container page page-xs"
    )
  end

  def create(conn, %{"username" => username, "email" => email_address}) do
    if user = Users.get_by_username(username, [:emails]) do
      if email = Enum.find(user.emails, &(&1.email == email_address)) do
        Users.email_verification(user, email)
      end
    end

    conn
    |> put_flash(:info, "A verification email has been sent to #{email_address}.")
    |> redirect(to: ~p"/")
  end
end
