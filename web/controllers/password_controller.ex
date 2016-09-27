defmodule HexWeb.PasswordController do
  use HexWeb.Web, :controller

  def reset(conn, _params) do
    render conn, "reset.html", [
      title: "Reset your password",
      container: "container page password-view",
      username: "username",
      key: "key"
    ]
  end

  def new(conn, %{"username" => username, "key" => key}) do
    render conn, "new.html", [
      title: "Choose a new password",
      container: "container page password-view",
      username: username,
      key: key
    ]
  end

  def choose(conn, %{"username" => username, "key" => key, "password" => password} = params) do
    revoke_all_keys? = Map.get(params, "revoke_all_keys", "yes") == "yes"
    success = Users.reset(username, key, password, revoke_all_keys?) == :ok
    title = if success, do: "Password reset", else: "Failed to reset password"

    render conn, "choose.html", [
      title: title,
      container: "container page password-view",
      success: success
    ]
  end
end
