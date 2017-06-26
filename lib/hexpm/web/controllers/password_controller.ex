defmodule Hexpm.Web.PasswordController do
  use Hexpm.Web, :controller

  def show(conn, %{"username" => username, "key" => key}) do
    conn
    |> put_session("reset_username", username)
    |> put_session("reset_key", key)
    |> redirect(to: password_path(conn, :show))
  end

  def show(conn, _params) do
    username = get_session(conn, "reset_username")
    key = get_session(conn, "reset_key")
    changeset = User.update_password(%User{}, %{})

    conn
    |> delete_session("reset_username")
    |> delete_session("reset_key")
    |> render_show(username, key, changeset)
  end

  def update(conn, params) do
    params = params["user"]
    username = params["username"]
    key = params["key"]
    revoke_all_keys? = (params["revoke_all_keys"] || "yes") == "yes"

    case Users.password_reset_finish(username, key, params, revoke_all_keys?, audit: audit_data(conn)) do
      :ok ->
        conn
        |> clear_session()
        |> configure_session(renew: true)
        |> put_flash(:info, "Your account password has been changed to your new password.")
        |> put_flash(:custom_location, true)
        |> redirect(to: page_path(Hexpm.Web.Endpoint, :index))
      :error ->
        conn
        |> put_flash(:error, "Failed to change your password.")
        |> put_flash(:custom_location, true)
        |> redirect(to: page_path(Hexpm.Web.Endpoint, :index))
      {:error, changeset} ->
        render_show(conn, username, key, changeset)
    end
  end

  defp render_show(conn, username, key, changeset) do
    render conn, "show.html", [
      title: "Choose a new password",
      container: "container page password-view",
      username: username,
      key: key,
      changeset: changeset
    ]
  end
end
