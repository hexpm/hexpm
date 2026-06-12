defmodule HexpmWeb.SignupController do
  use HexpmWeb, :controller

  def show(conn, _params) do
    if logged_in?(conn) do
      path = ~p"/users/#{conn.assigns.current_user}"
      redirect(conn, to: path)
    else
      changeset = User.build(signup_params(%{}))
      render_show(conn, changeset)
    end
  end

  def create(conn, params) do
    user_params = signup_params(params["user"])

    cond do
      logged_in?(conn) ->
        path = ~p"/users/#{conn.assigns.current_user}"
        redirect(conn, to: path)

      HexpmWeb.Captcha.verify(params["h-captcha-response"]) ->
        case Users.add(user_params, audit: audit_data(conn)) do
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
            |> put_flash(:error, "Oops, something went wrong! Please check the errors below.")
            |> render_show(changeset)
        end

      true ->
        changeset = %{User.build(sanitize_params(user_params)) | action: :insert}

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

  defp signup_params(params) when is_map(params) do
    Map.put(params, "emails", normalize_email_params(params["emails"]))
  end

  defp signup_params(_params), do: %{"emails" => empty_email_params()}

  defp normalize_email_params(%{} = emails) do
    emails
    |> Enum.sort_by(fn {index, _email_params} -> String.to_integer(index) end)
    |> Enum.map(fn {_index, email_params} -> email_params end)
    |> ensure_email_params()
  end

  defp normalize_email_params(emails) when is_list(emails), do: ensure_email_params(emails)
  defp normalize_email_params(_emails), do: empty_email_params()

  defp ensure_email_params([]), do: empty_email_params()
  defp ensure_email_params(emails), do: emails

  defp empty_email_params, do: [%{"email" => "", "email_confirmation" => ""}]
end
