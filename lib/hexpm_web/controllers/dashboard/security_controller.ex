defmodule HexpmWeb.Dashboard.SecurityController do
  use HexpmWeb, :controller
  alias Hexpm.Accounts.User
  plug :requires_login

  def index(conn, _params) do
    user = conn.assigns.current_user

    if User.tfa_enabled?(user) and not User.app_enabled?(user) do
      conn
      |> put_flash(:error, "Please complete your two-factor authentication setup")
      |> redirect(to: Routes.dashboard_tfa_setup_path(conn, :index))
    else
      render_index(conn, User.update_security(user, %{}))
    end
  end

  def update(conn, %{"user" => %{"tfa_enabled" => tfa_enabled}}) do
    user = conn.assigns.current_user

    case {User.tfa_enabled?(user), tfa_enabled} do
      {false, "true"} ->
        # need to redirect to the QR code setup page
        update_tfa_setting(user, conn, false, true)

      {true, "false"} ->
        update_tfa_setting(user, conn, true, false)

      _unchanged ->
        conn
        |> put_flash(:info, "Your security preference has been updated.")
        |> redirect(to: Routes.dashboard_security_path(conn, :index))
    end
  end

  def update(conn, %{"user" => %{"verification_code" => verification_code}} = _params) do
    user = conn.assigns.current_user

    if Hexpm.Accounts.TFA.token_valid?(user.tfa.secret, verification_code) do
      update_app_enabled(user, conn, true)
    else
      conn
      |> put_flash(:error, "Your verification code was incorrect.")
      |> redirect(to: Routes.dashboard_tfa_setup_path(conn, :index))
    end
  end

  def rotate_recovery_codes(conn, _params) do
    user = conn.assigns.current_user

    case Users.rotate_recovery_codes(user, audit: audit_data(conn)) do
      {:ok, _user} ->
        conn
        |> put_flash(:info, "New two-factor recovery codes successfully generated.")
        |> redirect(to: Routes.dashboard_security_path(conn, :index))

      {:error, changeset} ->
        conn
        |> put_status(400)
        |> render_index(changeset)
    end
  end

  def reset_auth_app(conn, _params) do
    user = conn.assigns.current_user
    reset_tfa_setting(user, conn)
  end

  defp render_index(conn, changeset) do
    render(
      conn,
      "index.html",
      title: "Dashboard - Security",
      container: "container page dashboard",
      changeset: changeset
    )
  end

  defp update_tfa_setting(user, conn, true, false) do
    case Users.update_security(user, %{"tfa_enabled" => "false"}, audit: audit_data(conn)) do
      {:ok, _user} ->
        conn
        |> put_flash(:info, "Your security preference has been updated.")
        |> redirect(to: Routes.dashboard_security_path(conn, :index))

      {:error, changeset} ->
        conn
        |> put_status(400)
        |> render_index(changeset)
    end
  end

  defp update_tfa_setting(user, conn, false, true) do
    case Users.update_security(user, %{"tfa_enabled" => "true"}, audit: audit_data(conn)) do
      {:ok, _user} ->
        conn
        |> put_flash(:info, "Your security preference has been updated.")
        |> redirect(to: Routes.dashboard_tfa_setup_path(conn, :index))

      {:error, changeset} ->
        conn
        |> put_status(400)
        |> render_index(changeset)
    end
  end

  defp update_app_enabled(user, conn, app_enabled?) do
    case Users.update_security(user, %{"app_enabled" => app_enabled?}, audit: audit_data(conn)) do
      {:ok, _user} ->
        conn
        |> put_flash(:info, "Your security preference has been updated.")
        |> redirect(to: Routes.dashboard_security_path(conn, :index))

      {:error, changeset} ->
        conn
        |> put_status(400)
        |> render_index(changeset)
    end
  end

  defp reset_tfa_setting(user, conn) do
    case Users.update_security(user, %{"tfa_enabled" => "true"}, audit: audit_data(conn)) do
      {:ok, _user} ->
        conn
        |> put_flash(:info, "Your security preference has been updated.")
        |> redirect(to: Routes.dashboard_tfa_setup_path(conn, :index))

      {:error, changeset} ->
        conn
        |> put_status(400)
        |> render_index(changeset)
    end
  end
end
