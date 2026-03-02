defmodule HexpmWeb.EmailVerificationController do
  use HexpmWeb, :controller

  def show(conn, _params) do
    render_show(conn)
  end

  def create(conn, %{"username" => username, "email" => email_address} = params) do
    if HexpmWeb.Captcha.verify(params["h-captcha-response"]) do
      if user = Users.get_by_username(username, [:emails]) do
        if email = Enum.find(user.emails, &(&1.email == email_address)) do
          Users.email_verification(user, email)
        end
      end

      conn
      |> put_flash(
        :info,
        "If this email exists in our database and is not already verified, you will receive a verification link at informed email: #{email_address}."
      )
      |> redirect(to: ~p"/")
    else
      conn
      |> put_status(400)
      |> put_flash(:error, "Oops, something went wrong!")
      |> render_show("Please complete the captcha to send verification email")
    end
  end

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

  defp render_show(conn, captcha_error \\ nil) do
    render(
      conn,
      "show.html",
      title: "Verify email",
      captcha_error: captcha_error
    )
  end
end
