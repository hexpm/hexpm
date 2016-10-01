defmodule HexWeb.PasswordController do
  use HexWeb.Web, :controller

  def show(conn, %{"username" => username, "key" => key}) do
    render conn, "show.html", [
      title: "Choose a new password",
      container: "container page password-view",
      username: username,
      key: key
    ]
  end

  def update(conn, %{"username" => username, "key" => key, "password" => password} = params) do
    revoke_all_keys? = Map.get(params, "revoke_all_keys", "yes") == "yes"
    success = Users.reset(username, key, password, revoke_all_keys?) == :ok

    render conn, "update.html", [
      title: "Choose a new password",
      container: "container page password-view",
      success: success
    ]
  end
end
