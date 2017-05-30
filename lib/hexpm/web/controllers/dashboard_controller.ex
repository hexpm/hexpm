defmodule Hexpm.Web.DashboardController do
  use Hexpm.Web, :controller

  plug :requires_login

  def index(conn, _params) do
    redirect(conn, to: dashboard_path(conn, :profile))
  end

  def profile(conn, _params) do
    user = conn.assigns.logged_in
    render_profile(conn, User.update_profile(user, %{}))
  end

  def update_profile(conn, params) do
    user = conn.assigns.logged_in

    case Users.update_profile(user, params["user"], audit: audit_data(conn)) do
      {:ok, _user} ->
        conn
        |> put_flash(:info, "Profile updated successfully.")
        |> redirect(to: dashboard_path(conn, :profile))
      {:error, changeset} ->
        conn
        |> put_status(400)
        |> render_profile(changeset)
    end
  end

  def password(conn, _params) do
    user = conn.assigns.logged_in
    render_password(conn, User.update_password(user, %{}))
  end

  def update_password(conn, params) do
    user = conn.assigns.logged_in

    case Users.update_password(user, params["user"], audit: audit_data(conn)) do
      {:ok, _user} ->
        # TODO: Maybe send an email here?
        conn
        |> put_flash(:info, "Your password has been updated.")
        |> redirect(to: dashboard_path(conn, :password))
      {:error, changeset} ->
        conn
        |> put_status(400)
        |> render_password(changeset)
    end
  end

  def email(conn, _params) do
    user = Users.with_emails(conn.assigns.logged_in)
    render_email(conn, user)
  end

  def add_email(conn, params) do
    user = Users.with_emails(conn.assigns.logged_in)

    case Users.add_email(user, params["email"], audit: audit_data(conn)) do
      {:ok, _user} ->
        email = params["email"]["email"]
        conn
        |> put_flash(:info, "A verification email has been sent to #{email}.")
        |> redirect(to: dashboard_path(conn, :email))
      {:error, changeset} ->
        conn
        |> put_status(400)
        |> render_email(user, changeset)
    end
  end

  def remove_email(conn, params) do
    user = Users.with_emails(conn.assigns.logged_in)
    email = params["email"]

    case Users.remove_email(user, params, audit: audit_data(conn)) do
      :ok ->
        conn
        |> put_flash(:info, "Removed email #{email} from your account.")
        |> redirect(to: dashboard_path(conn, :email))
      {:error, reason} ->
        conn
        |> put_flash(:error, email_error_message(reason, email))
        |> redirect(to: dashboard_path(conn, :email))
    end
  end

  def primary_email(conn, params) do
    user = Users.with_emails(conn.assigns.logged_in)
    email = params["email"]

    case Users.primary_email(user, params, audit: audit_data(conn)) do
      :ok ->
        conn
        |> put_flash(:info, "Your primary email was changed to #{email}.")
        |> redirect(to: dashboard_path(conn, :email))
      {:error, reason} ->
        conn
        |> put_flash(:error, email_error_message(reason, email))
        |> redirect(to: dashboard_path(conn, :email))
    end
  end

  def public_email(conn, params) do
    user = Users.with_emails(conn.assigns.logged_in)
    email = params["email"]

    case Users.public_email(user, params, audit: audit_data(conn)) do
      :ok ->
        conn
        |> put_flash(:info, "Your public email was changed to #{email}.")
        |> redirect(to: dashboard_path(conn, :email))
      {:error, reason} ->
        conn
        |> put_flash(:error, email_error_message(reason, email))
        |> redirect(to: dashboard_path(conn, :email))
    end
  end

  def resend_verify_email(conn, params) do
    user = Users.with_emails(conn.assigns.logged_in)
    email = params["email"]

    case Users.resend_verify_email(user, params) do
      :ok ->
        conn
        |> put_flash(:info, "A verification email has been sent to #{email}.")
        |> redirect(to: dashboard_path(conn, :email))
      {:error, reason} ->
        conn
        |> put_flash(:error, email_error_message(reason, email))
        |> redirect(to: dashboard_path(conn, :email))
    end
  end

  def twofactor(conn, _params) do
    user = conn.assigns.logged_in
    changeset = User.setup_twofactor(user, %{})
    enabled? = user.twofactor.enabled
    backupcodes = User.backupcodes(user)

    render_twofactor(conn, changeset, backupcodes, enabled?)
  end

  def toggle_twofactor(conn, params) do
    user = conn.assigns.logged_in
    enabled? = user.twofactor.enabled

    if enabled? do
      case Users.disable_twofactor(user, params["user"], audit: audit_data(conn)) do
        {:ok, _user} ->
          conn
          |> put_flash(:info, "Two-factor authentication is now disabled.")
          |> redirect(to: dashboard_path(conn, :twofactor))
        {:error, _changeset} ->
          conn
          |> put_flash(:error, "An internal error occured. Please try again.")
          |> redirect(to: dashboard_path(conn, :twofactor))
      end
    else
      # TODO: check that this hasn't already been done
      case Users.setup_twofactor(user, params["user"], audit: audit_data(conn)) do
        {:ok, _user} ->
          conn
          |> redirect(to: dashboard_path(conn, :show_qrcode_twofactor))
        {:error, _changeset} ->
          conn
          |> put_flash(:error, "An internal error occured. Please try again.")
          |> redirect(to: dashboard_path(conn, :twofactor))
      end
    end
  end

  def show_qrcode_twofactor(conn, _params) do
    user = conn.assigns.logged_in

    enabled? = user.twofactor.enabled
    secret_set? = String.length(user.twofactor.secret) > 0 # TODO: better approach

    if !enabled? and secret_set? do
      changeset = User.setup_twofactor(user, %{})
      totp = User.totp(user, true)
      render_twofactor_confirm_totp(conn, changeset, totp)
    else
      conn
      |> redirect(to: dashboard_path(conn, :twofactor))
    end
  end

  def confirm_twofactor(conn, params) do
    user = conn.assigns.logged_in
    totp = User.totp(user, true)
    pin = params["user"]["pin"]

    case TOTP.verify(totp, pin) do
      true ->
        case Users.enable_twofactor(user, params["user"], audit: audit_data(conn)) do
          {:ok, _user} ->
            conn
            |> put_flash(:info, "Two-factor authentication is now enabled.")
            |> redirect(to: dashboard_path(conn, :twofactor))
          {:error, _changeset} ->
            conn
            |> put_flash(:error, "An internal error occured. Please try again.")
            |> redirect(to: dashboard_path(conn, :show_qrcode_twofactor))
        end
      _ ->
        conn
        |> put_flash(:error, "The code you entered was incorrect.")
        |> redirect(to: dashboard_path(conn, :show_qrcode_twofactor))
    end
  end

  def regen_backup_twofactor(conn, params) do
    user = conn.assigns.logged_in

    case Users.regen_twofactor_backupcodes(user, params["user"], audit: audit_data(conn)) do
      {:ok, _user} ->
        conn
        |> put_flash(:info, "Your backup codes have been regenerated. Scroll down to make a copy.")
        |> redirect(to: dashboard_path(conn, :twofactor))
      {:error, _changeset} ->
        conn
        |> put_flash(:error, "Could not regenerate backup codes.")
        |> redirect(to: dashboard_path(conn, :twofactor))
    end
  end

  defp render_profile(conn, changeset) do
    render conn, "profile.html", [
      title: "Dashboard - Public profile",
      container: "container page dashboard",
      changeset: changeset
    ]
  end

  defp render_password(conn, changeset) do
    render conn, "password.html", [
      title: "Dashboard - Change password",
      container: "container page dashboard",
      changeset: changeset
    ]
  end

  defp render_email(conn, user, add_email_changeset \\ add_email_changeset()) do
    emails = Email.order_emails(user.emails)

    render conn, "email.html", [
      title: "Dashboard - Email",
      container: "container page dashboard",
      add_email_changeset: add_email_changeset,
      emails: emails
    ]
  end

  defp render_twofactor(conn, changeset, backupcodes, enabled?) do
    render conn, "twofactor.html", [
      title: "Dashboard - 2FA",
      container: "container page dashboard",
      changeset: changeset,
      types: ["TOTP": "totp"],
      backupcodes: backupcodes,
      enabled: enabled?
    ]
  end

  defp render_twofactor_confirm_totp(conn, changeset, totp) do
    render conn, "twofactor_confirm_totp.html", [
      title: "Dashboard - 2FA",
      container: "container page dashboard",
      changeset: changeset,
      totp: totp
    ]
  end

  defp add_email_changeset do
    Email.changeset(%Email{}, :create, %{}, false)
  end

  defp email_error_message(:unknown_email, email), do: "Unknown email #{email}."
  defp email_error_message(:not_verified, email), do: "Email #{email} not verified."
  defp email_error_message(:already_verified, email), do: "Email #{email} already verified."
  defp email_error_message(:primary, email), do: "Cannot remove primary email #{email}."
end
