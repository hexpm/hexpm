defmodule HexpmWeb.Dashboard.SecurityController do
  use HexpmWeb, :controller
  alias Hexpm.Accounts.{User, Users, UserProviders}

  plug :requires_login

  def index(conn, _params) do
    user = conn.assigns.current_user

    if User.tfa_enabled?(user) and not user.tfa.app_enabled do
      conn
      |> put_flash(:error, "Please complete your two-factor authentication setup")
      |> redirect(to: ~p"/dashboard/tfa/setup")
    else
      render_index(conn, User.update_password(user, %{}))
    end
  end

  def enable_tfa(conn, _params) do
    user = conn.assigns.current_user
    Users.tfa_enable(user, audit: audit_data(conn))

    conn
    |> put_flash(:info, "Two factor authentication has been enabled.")
    |> redirect(to: ~p"/dashboard/tfa/setup")
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
    |> put_flash(:info, "Please complete your two-factor authentication setup")
    |> redirect(to: ~p"/dashboard/tfa/setup")
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
        errors = HexpmWeb.ControllerHelpers.translate_errors(changeset)
        error_message = errors |> Map.values() |> List.flatten() |> Enum.join(", ")

        conn
        |> put_flash(:error, "Failed to add password: #{error_message}")
        |> redirect(to: ~p"/dashboard/security")
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
    render(
      conn,
      "index.html",
      title: "Dashboard - Security",
      container: "container page dashboard",
      password_changeset: password_changeset
    )
  end

  defp maybe_put_flash(conn, false), do: conn

  defp maybe_put_flash(conn, true) do
    put_flash(conn, :raw_error, password_breached_message())
  end
end
