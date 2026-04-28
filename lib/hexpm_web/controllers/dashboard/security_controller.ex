defmodule HexpmWeb.Dashboard.SecurityController do
  use HexpmWeb, :controller
  alias Hexpm.Accounts.{TFA, User, Users, UserProviders}

  plug :requires_login
  plug HexpmWeb.Plugs.Sudo

  def index(conn, params) do
    user = conn.assigns.current_user
    tfa_error = params["tfa_error"]
    show_modal = params["show_tfa_modal"]
    tfa_secret = get_session(conn, :tfa_setup_secret)

    cond do
      # TFA error - reopen modal with error
      tfa_error == "invalid_code" and tfa_secret ->
        conn
        |> assign(:show_tfa_modal, true)
        |> assign(:tfa_error, "invalid_code")
        |> assign(:tfa_secret, tfa_secret)
        |> render_index(User.update_password(user, %{}))

      # User clicked "Enable" OR "Setup New App" - show modal for setup
      show_modal == "true" and tfa_secret ->
        conn
        |> assign(:show_tfa_modal, true)
        |> assign(:tfa_error, nil)
        |> assign(:tfa_secret, tfa_secret)
        |> render_index(User.update_password(user, %{}))

      # Normal case
      true ->
        conn
        |> assign(:show_tfa_modal, false)
        |> assign(:tfa_error, nil)
        |> assign(:tfa_secret, nil)
        |> render_index(User.update_password(user, %{}))
    end
  end

  def enable_tfa(conn, _params) do
    # Generate secret and store in session (not in DB)
    # TFA will only be enabled after user verifies the code
    secret = TFA.generate_secret()

    conn
    |> put_session(:tfa_setup_secret, secret)
    |> put_flash(
      :info,
      "Please scan the QR code to complete two-factor authentication setup."
    )
    |> redirect(to: ~p"/dashboard/security?show_tfa_modal=true")
  end

  def disable_tfa(conn, _params) do
    user = conn.assigns.current_user
    Users.tfa_disable(user, audit: audit_data(conn))

    conn
    |> delete_session(:tfa_setup_secret)
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
    Users.tfa_disable(user, audit: audit_data(conn))

    # Generate new secret in session for re-setup
    secret = TFA.generate_secret()

    conn
    |> put_session(:tfa_setup_secret, secret)
    |> put_flash(:info, "Please scan the new QR code with your authenticator app")
    |> redirect(to: ~p"/dashboard/security?show_tfa_modal=true")
  end

  def verify_tfa_code(conn, %{"verification_code" => verification_code}) do
    user = conn.assigns.current_user
    secret = get_session(conn, :tfa_setup_secret)

    cond do
      User.tfa_enabled?(user) ->
        conn
        |> delete_session(:tfa_setup_secret)
        |> put_flash(:info, "Two-factor authentication is already enabled.")
        |> redirect(to: ~p"/dashboard/security")

      secret ->
        case Users.tfa_enable(user, secret, verification_code, audit: audit_data(conn)) do
          {:ok, _user} ->
            conn
            |> delete_session(:tfa_setup_secret)
            |> put_flash(:info, "Two-factor authentication has been successfully enabled!")
            |> redirect(to: ~p"/dashboard/security")

          :error ->
            conn
            |> put_flash(:error, "Your verification code was incorrect. Please try again.")
            |> redirect(to: ~p"/dashboard/security?tfa_error=invalid_code")

          {:error, _changeset} ->
            conn
            |> put_flash(:error, "Failed to enable two-factor authentication. Please try again.")
            |> redirect(to: ~p"/dashboard/security?show_tfa_modal=true")
        end

      true ->
        conn
        |> put_flash(:error, "Two-factor authentication setup has not been started.")
        |> redirect(to: ~p"/dashboard/security")
    end
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
      conn.assigns[:add_password_changeset] ||
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
end
