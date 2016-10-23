defmodule HexWeb.PasswordController do
  use HexWeb.Web, :controller

  def show(conn, %{"username" => username, "key" => key}) do
    path = password_path(conn, :show)

    conn
    |> put_resp_cookie("reset_username", username, max_age: 60, path: path)
    |> put_resp_cookie("reset_key", key, max_age: 60, path: path)
    |> redirect(to: path)
  end

  def show(conn, _params) do
    username = conn.req_cookies["reset_username"]
    key = conn.req_cookies["reset_key"]
    changeset = User.update_password(%User{}, %{})

    render_show(conn, username, key, changeset)
  end

  def update(conn, params) do
    params = params["user"]
    username = params["username"]
    key = params["key"]
    revoke_all_keys? = (params["revoke_all_keys"] || "yes") == "yes"

    case Users.password_reset_finish(username, key, params, revoke_all_keys?, audit: audit_data(conn)) do
      :ok ->
        conn
        |> put_flash(:info, "Your account password has been changed to your new password.")
        |> put_flash(:custom_location, true)
        |> redirect(to: "/")
      :error ->
        conn
        |> put_flash(:error, "Failed to change your password.")
        |> put_flash(:custom_location, true)
        |> redirect(to: "/")
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
