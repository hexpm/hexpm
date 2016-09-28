defmodule HexWeb.PasswordController do
  use HexWeb.Web, :controller

  def show_reset(conn, _params) do
    render conn, "show_reset.html", [
      title: "Reset your password",
      container: "container page password-view"
    ]
  end

  def submit_reset(conn, %{"username" => name}) do
    Users.request_reset(name)

    render conn, "submit_reset.html", [
      title: "Reset your password",
      container: "container page password-view"
    ]
  end

  def show_new(conn, %{"username" => username, "key" => key}) do
    render conn, "show_new.html", [
      title: "Choose a new password",
      container: "container page password-view",
      username: username,
      key: key
    ]
  end

  def submit_new(conn, %{"username" => username, "key" => key, "password" => password} = params) do
    revoke_all_keys? = Map.get(params, "revoke_all_keys", "yes") == "yes"
    success = Users.reset(username, key, password, revoke_all_keys?) == :ok

    render conn, "submit_new.html", [
      title: "Choose a new password",
      container: "container page password-view",
      success: success
    ]
  end
end
