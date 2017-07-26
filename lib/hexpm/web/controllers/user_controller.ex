defmodule Hexpm.Web.UserController do
  use Hexpm.Web, :controller

  def show(conn, %{"username" => username}) do
    if user = Users.get_by_username(username, [:emails, owned_packages: :repository]) do
      packages = Packages.attach_versions(user.owned_packages) |> Enum.sort_by(& &1.name)
      public_email = User.email(user, :public)

      render(conn, "show.html", [
        title: user.username,
        container: "container page user",
        user: user,
        packages: packages,
        public_email: public_email
      ])
    else
      not_found(conn)
    end
  end
end
