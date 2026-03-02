defmodule HexpmWeb.Dashboard.SecurityController do
  use HexpmWeb, :controller
  alias Hexpm.Accounts.{User, Users, UserProviders}
  import Hexpm.Accounts.AuditLog, only: [audit: 4]

  plug :requires_login

  def index(conn, params) do
    user = conn.assigns.current_user
    tfa_error = params["tfa_error"]
    show_modal = params["show_tfa_modal"]

    cond do
      # TFA error - reopen modal with error
      tfa_error == "invalid_code" and has_tfa_secret?(user) ->
        conn
        |> assign(:show_tfa_modal, true)
        |> assign(:tfa_error, "invalid_code")
        |> render_index(User.update_password(user, %{}))

      # User clicked "Enable" OR "Setup New App" - show modal for setup
      show_modal == "true" and has_tfa_secret?(user) ->
        conn
        |> assign(:show_tfa_modal, true)
        |> assign(:tfa_error, nil)
        |> render_index(User.update_password(user, %{}))

      # Normal case
      true ->
        conn
        |> assign(:show_tfa_modal, false)
        |> assign(:tfa_error, nil)
        |> render_index(User.update_password(user, %{}))
    end
  end

  def enable_tfa(conn, _params) do
    user = conn.assigns.current_user

    # Generate secret but DON'T enable TFA yet
    # TFA will only be enabled after user verifies the code
    secret = Hexpm.Accounts.TFA.generate_secret()
    codes = Hexpm.Accounts.RecoveryCode.generate_set()

    case Hexpm.Repo.update(
           Hexpm.Accounts.User.update_tfa(user, %{
             secret: secret,
             recovery_codes: codes,
             # Keep disabled until verified!
             tfa_enabled: false,
             app_enabled: false
           })
         ) do
      {:ok, updated_user} ->
        conn
        |> assign(:current_user, updated_user)
        |> put_flash(
          :info,
          "Please scan the QR code to complete two-factor authentication setup."
        )
        |> redirect(to: ~p"/dashboard/security?show_tfa_modal=true")

      {:error, _changeset} ->
        conn
        |> put_flash(:error, "Failed to initialize two-factor authentication. Please try again.")
        |> redirect(to: ~p"/dashboard/security")
    end
  end

  def disable_tfa(conn, _params) do
    user = conn.assigns.current_user
    Users.tfa_disable(user, audit: audit_data(conn))

    conn
    |> put_flash(:info, "Two factor authentication has been disabled.")
    |> redirect(to: ~p"/dashboard/security")
  end

  def rotate_recovery_codes(conn, _params) do
    user = conn.assigns.current_user
    Users.tfa_rotate_recovery_codes(user, audit: audit_data(conn))

    conn
    |> put_flash(:info, "New two-factor recovery codes successfully generated.")
    |> redirect(to: ~p"/dashboard/security")
  end

  def reset_auth_app(conn, _params) do
    user = conn.assigns.current_user
    Users.tfa_disable_app(user, audit: audit_data(conn))

    conn
    |> put_flash(:info, "Please scan the new QR code with your authenticator app")
    |> redirect(to: ~p"/dashboard/security?show_tfa_modal=true")
  end

  def change_password(conn, params) do
    user = conn.assigns.current_user

    case Users.update_password(user, params["user"], audit: audit_data(conn)) do
      {:ok, _user} ->
        breached? = Hexpm.Pwned.password_breached?(params["user"]["password"])

        conn
        |> put_flash(:info, "Your password has been updated.")
        |> maybe_put_flash(breached?)
        |> redirect(to: ~p"/dashboard/security")

      {:error, changeset} ->
        conn
        |> put_status(400)
        |> render_index(changeset)
    end
  end

  def disconnect_github(conn, _params) do
    user = Hexpm.Repo.preload(conn.assigns.current_user, :user_providers)

    case UserProviders.get_for_user(user, "github") do
      nil ->
        conn
        |> put_flash(:error, "GitHub account is not connected.")
        |> redirect(to: ~p"/dashboard/security")

      user_provider ->
        if User.can_remove_provider?(user, "github") do
          case UserProviders.delete(user_provider, audit: audit_data(conn)) do
            :ok ->
              conn
              |> put_flash(:info, "GitHub account disconnected successfully.")
              |> redirect(to: ~p"/dashboard/security")

            {:error, _changeset} ->
              conn
              |> put_flash(:error, "Failed to disconnect GitHub account.")
              |> redirect(to: ~p"/dashboard/security")
          end
        else
          conn
          |> put_flash(:error, "Cannot disconnect GitHub account. Please add a password first.")
          |> redirect(to: ~p"/dashboard/security")
        end
    end
  end

  def add_password(conn, %{"user" => params}) do
    user = conn.assigns.current_user

    case Users.add_password_to_user(user, params, audit: audit_data(conn)) do
      {:ok, _user} ->
        breached? = Hexpm.Pwned.password_breached?(params["password"])

        conn
        |> put_flash(:info, "Password added successfully.")
        |> maybe_put_flash(breached?)
        |> redirect(to: ~p"/dashboard/security")

      {:error, changeset} ->
        conn
        |> put_status(400)
        |> assign(:add_password_changeset, changeset)
        |> render_index(User.update_password(user, %{}))
    end
  end

  def remove_password(conn, _params) do
    user = Hexpm.Repo.preload(conn.assigns.current_user, :user_providers)

    case Users.remove_password_from_user(user, audit: audit_data(conn)) do
      {:ok, _user} ->
        conn
        |> put_flash(:info, "Password removed successfully.")
        |> redirect(to: ~p"/dashboard/security")

      {:error, changeset} ->
        errors = HexpmWeb.ControllerHelpers.translate_errors(changeset)
        error_message = errors |> Map.values() |> List.flatten() |> Enum.join(", ")

        conn
        |> put_flash(:error, "Failed to remove password: #{error_message}")
        |> redirect(to: ~p"/dashboard/security")
    end
  end

  defp render_index(conn, password_changeset) do
    user = conn.assigns.current_user

    add_password_changeset =
      if user.password do
        User.update_password(user, %{})
      else
        User.add_password(user, %{})
      end

    render(
      conn,
      "index.html",
      title: "Dashboard - Security",
      container: "container page dashboard",
      password_changeset: password_changeset,
      add_password_changeset: add_password_changeset
    )
  end

  defp maybe_put_flash(conn, false), do: conn

  defp maybe_put_flash(conn, true) do
    put_flash(conn, :raw_error, password_breached_message())
  end

  def verify_tfa_code(conn, %{"verification_code" => verification_code}) do
    user = conn.assigns.current_user

    cond do
      not has_tfa_secret?(user) ->
        conn
        |> put_flash(:error, "Two-factor authentication setup has not been started.")
        |> redirect(to: ~p"/dashboard/security")

      not Hexpm.Accounts.TFA.token_valid?(user.tfa.secret, verification_code) ->
        conn
        |> put_flash(:error, "Your verification code was incorrect. Please try again.")
        |> redirect(to: ~p"/dashboard/security?tfa_error=invalid_code")

      true ->
        enable_tfa_for_user(conn, user)
    end
  end

  defp enable_tfa_for_user(conn, user) do
    multi =
      Ecto.Multi.new()
      |> Ecto.Multi.update(
        :user,
        User.update_tfa(user, %{tfa_enabled: true, app_enabled: true})
      )
      |> audit(audit_data(conn), "security.update", fn %{user: user} -> user end)

    case Hexpm.Repo.transaction(multi) do
      {:ok, %{user: updated_user}} ->
        updated_user
        |> Hexpm.Emails.tfa_enabled()
        |> Hexpm.Emails.Mailer.deliver_later!()

        conn
        |> put_flash(:info, "Two-factor authentication has been successfully enabled!")
        |> redirect(to: ~p"/dashboard/security")

      {:error, :user, _changeset, _} ->
        conn
        |> put_flash(:error, "Failed to enable two-factor authentication. Please try again.")
        |> redirect(to: ~p"/dashboard/security?show_tfa_modal=true")
    end
  end

  defp has_tfa_secret?(user) do
    user.tfa != nil and is_struct(user.tfa) and user.tfa.secret != nil
  end
end
