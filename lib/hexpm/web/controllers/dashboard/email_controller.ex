defmodule HexpmWeb.Dashboard.EmailController do
  use HexpmWeb, :controller

  plug :requires_login

  def index(conn, _params) do
    render_index(conn, conn.assigns.current_user)
  end

  def create(conn, %{"email" => email_params}) do
    user = conn.assigns.current_user

    case Users.add_email(user, email_params, audit: audit_data(conn)) do
      {:ok, _user} ->
        email = email_params["email"]

        conn
        |> put_flash(:info, "A verification email has been sent to #{email}.")
        |> redirect(to: Routes.email_path(conn, :index))

      {:error, changeset} ->
        conn
        |> put_status(400)
        |> render_index(user, changeset)
    end
  end

  def delete(conn, %{"email" => email} = params) do
    case Users.remove_email(conn.assigns.current_user, params, audit: audit_data(conn)) do
      :ok ->
        conn
        |> put_flash(:info, "Removed email #{email} from your account.")
        |> redirect(to: Routes.email_path(conn, :index))

      {:error, reason} ->
        conn
        |> put_flash(:error, email_error_message(reason, email))
        |> redirect(to: Routes.email_path(conn, :index))
    end
  end

  def primary(conn, %{"email" => email} = params) do
    case Users.primary_email(conn.assigns.current_user, params, audit: audit_data(conn)) do
      :ok ->
        conn
        |> put_flash(:info, "Your primary email was changed to #{email}.")
        |> redirect(to: Routes.email_path(conn, :index))

      {:error, reason} ->
        conn
        |> put_flash(:error, email_error_message(reason, email))
        |> redirect(to: Routes.email_path(conn, :index))
    end
  end

  def public(conn, %{"email" => email} = params) do
    case Users.public_email(conn.assigns.current_user, params, audit: audit_data(conn)) do
      :ok ->
        conn
        |> put_flash(:info, "Your public email was changed to #{email}.")
        |> redirect(to: Routes.email_path(conn, :index))

      {:error, reason} ->
        conn
        |> put_flash(:error, email_error_message(reason, email))
        |> redirect(to: Routes.email_path(conn, :index))
    end
  end

  def gravatar(conn, %{"email" => email} = params) do
    case Users.gravatar_email(conn.assigns.current_user, params, audit: audit_data(conn)) do
      :ok ->
        conn
        |> put_flash(:info, "Your gravatar email was changed to #{email}.")
        |> redirect(to: Routes.email_path(conn, :index))

      {:error, reason} ->
        conn
        |> put_flash(:error, email_error_message(reason, email))
        |> redirect(to: Routes.email_path(conn, :index))
    end
  end

  def resend_verify(conn, %{"email" => email} = params) do
    case Users.resend_verify_email(conn.assigns.current_user, params) do
      :ok ->
        conn
        |> put_flash(:info, "A verification email has been sent to #{email}.")
        |> redirect(to: Routes.email_path(conn, :index))

      {:error, reason} ->
        conn
        |> put_flash(:error, email_error_message(reason, email))
        |> redirect(to: Routes.email_path(conn, :index))
    end
  end

  defp render_index(conn, user, create_changeset \\ create_changeset()) do
    emails = Email.order_emails(user.emails)

    render(
      conn,
      "index.html",
      title: "Dashboard - Email",
      container: "container page dashboard",
      create_changeset: create_changeset,
      emails: emails
    )
  end

  defp create_changeset() do
    Email.changeset(%Email{}, :create, %{}, false)
  end

  defp email_error_message(:unknown_email, email), do: "Unknown email #{email}."
  defp email_error_message(:not_verified, email), do: "Email #{email} not verified."
  defp email_error_message(:already_verified, email), do: "Email #{email} already verified."
  defp email_error_message(:primary, email), do: "Cannot remove primary email #{email}."
end
