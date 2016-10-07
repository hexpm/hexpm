defmodule HexWeb.UserController do
  use HexWeb.Web, :controller

  def show(conn, %{"username" => username}) do
    if user = Users.get_by_username(username) do
      user = Users.with_owned_packages(user)
      packages = Packages.attach_versions(user.owned_packages) |> Enum.sort_by(& &1.name)

      render conn, "show.html",
        title: user.username,
        container: "container page user",
        user: user,
        packages: packages
    else
      not_found(conn)
    end
  end

  def edit(conn, %{"username" => username}) do
    user = Users.get_by_username(username)

    if username == get_session(conn, "username") && user do
      render_edit(conn, User.update_profile(user, %{}))
    else
      not_found(conn)
    end
  end

  def update(conn, %{"username" => username} = params) do
    user = Users.get_by_username(username)

    if username == get_session(conn, "username") && user do
      case Users.update(user, params["user"]) do
        {:ok, user} ->
          redirect(conn, to: user_path(conn, :show, user))
        {:error, changeset} ->
          render_edit(conn, changeset)
      end
    else
      not_found(conn)
    end
  end

  defp render_edit(conn, changeset) do
    render conn, "edit.html",
      title: "Update your profile",
      container: "container page user-edit",
      changeset: changeset
  end
end
