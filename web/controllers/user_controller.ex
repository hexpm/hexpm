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
end
