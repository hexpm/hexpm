defmodule HexpmWeb.PasswordController do
  use HexpmWeb, :controller

  def show(conn, %{"username" => username, "key" => key}) do
    conn
    |> put_session("reset_username", username)
    |> put_session("reset_key", key)
    |> redirect(to: ~p"/password/new")
  end

  def show(conn, _params) do
    username = get_session(conn, "reset_username")
    key = get_session(conn, "reset_key")

    with {:ok, username} <- validate_session_params(username, key),
         :ok <- validate_reset_key(username, key) do
      changeset = User.update_password(%User{}, %{})
      render_show(conn, username, key, changeset)
    else
      {:error, :missing_session} ->
        conn
        |> put_flash(:error, "Invalid password reset key.")
        |> redirect(to: ~p"/")

      {:error, :invalid_key} ->
        conn
        |> delete_session("reset_username")
        |> delete_session("reset_key")
        |> put_flash(:error, "This password reset link has expired or already been used.")
        |> redirect(to: ~p"/password/reset")
    end
  end

  def update(conn, params) do
    params = params["user"]
    username = params["username"]
    key = params["key"]
    revoke_all_access? = (params["revoke_all_access"] || "yes") == "yes"

    case Users.password_reset_finish(
           username,
           key,
           params,
           revoke_all_access?,
           audit: audit_data(conn)
         ) do
      :ok ->
        breached? = Hexpm.Pwned.password_breached?(params["password"])

        conn
        |> clear_session()
        |> configure_session(renew: true)
        |> maybe_put_flash(breached?)
        |> put_flash(:info, "Your account password has been changed to your new password.")
        |> redirect(to: ~p"/")

      :error ->
        conn
        |> delete_session("reset_username")
        |> delete_session("reset_key")
        |> put_flash(
          :error,
          "This password reset link has expired or already been used. Please request a new one."
        )
        |> redirect(to: ~p"/password/reset")

      {:error, changeset} ->
        conn
        |> put_status(400)
        |> render_show(username, key, changeset)
    end
  end

  defp render_show(conn, username, key, changeset) do
    render(
      conn,
      "show.html",
      title: "Choose a new password",
      username: username,
      key: key,
      changeset: changeset
    )
  end

  defp validate_session_params(username, key) when is_binary(username) and is_binary(key) do
    {:ok, username}
  end

  defp validate_session_params(_username, _key) do
    {:error, :missing_session}
  end

  defp validate_reset_key(username, key) do
    # Need to preload both :password_resets and :emails for can_reset_password?
    user = Users.get(username, [:emails, :password_resets])

    if user && User.can_reset_password?(user, key) do
      :ok
    else
      {:error, :invalid_key}
    end
  end

  defp maybe_put_flash(conn, false), do: conn

  defp maybe_put_flash(conn, true) do
    put_flash(conn, :raw_error, password_breached_message())
  end
end
