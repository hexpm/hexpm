defmodule HexWeb.PasswordController do
  use HexWeb.Web, :controller

  def show_confirm(conn, %{"username" => username, "key" => key}) do
    success = Users.confirm(username, key) == :ok

    render conn, "confirm.html", [
      success: success
    ]
  end

  def show_reset(conn, %{"username" => username, "key" => key}) do
    render conn, "reset.html", [
      username: username,
      key: key
    ]
  end

  def reset(conn, %{"username" => username, "key" => key, "password" => password} = params) do
    revoke_all_keys? = Map.get(params, "revoke_all_keys", "yes") == "yes"
    success = Users.reset(username, key, password, revoke_all_keys?) == :ok

    render conn, "reset_result.html", [
      success: success
    ]
  end
end
