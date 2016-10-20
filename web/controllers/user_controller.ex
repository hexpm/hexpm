defmodule HexWeb.UserController do
  use HexWeb.Web, :controller

  def show(conn, %{"username" => username}) do
    if user = Users.get_by_username(username) do
      user =
        user
        |> Users.with_owned_packages
        |> Users.with_emails
      packages = Packages.attach_versions(user.owned_packages) |> Enum.sort_by(& &1.name)
      # NOTE: Disabled while waiting for privacy policy grace period
      public_email = nil # User.email(user, :public)

      render conn, "show.html",
        title: user.username,
        container: "container page user",
        user: user,
        packages: packages,
        public_email: public_email
    else
      not_found(conn)
    end
  end
end
