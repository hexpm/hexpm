defmodule HexpmWeb.UserController do
  use HexpmWeb, :controller

  def show(conn, %{"username" => username}) do
    if user = Users.get_by_username(username, [:emails, owned_packages: :organization]) do
      packages =
        Packages.accessible_user_owned_packages(user, conn.assigns.current_user)
        |> Packages.attach_versions()

      public_email = User.email(user, :public)
      gravatar_email = User.email(user, :gravatar)

      render(
        conn,
        "show.html",
        title: user.username,
        container: "container page user",
        user: user,
        packages: packages,
        public_email: public_email,
        gravatar_email: gravatar_email
      )
    else
      not_found(conn)
    end
  end
end
