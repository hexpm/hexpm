defmodule HexpmWeb.UserController do
  use HexpmWeb, :controller

  def show(conn, %{"username" => username}) do
    user =
      Users.get_by_username(username, [
        :emails,
        :organization,
        owned_packages: [:repository, :downloads]
      ])

    if user do
      organization = user.organization

      case conn.path_info do
        ["users" | _] when not is_nil(organization) ->
          redirect(conn, to: Router.user_path(user))

        ["orgs" | _] when is_nil(organization) ->
          redirect(conn, to: Router.user_path(user))

        _ ->
          show_user(conn, user)
      end
    else
      not_found(conn)
    end
  end

  defp show_user(conn, user) do
    packages =
      Packages.accessible_user_owned_packages(user, conn.assigns.current_user)
      |> Packages.attach_versions()

    downloads = Packages.packages_downloads_with_all_views(packages)

    total_downloads =
      Enum.reduce(downloads, 0, fn {_id, d}, acc -> acc + Map.get(d, "all", 0) end)

    public_email = User.email(user, :public)
    gravatar_email = User.email(user, :gravatar)

    render(
      conn,
      "show.html",
      title: user.username,
      container: "container page user",
      user: user,
      packages: packages,
      downloads: downloads,
      total_downloads: total_downloads,
      public_email: public_email,
      gravatar_email: gravatar_email
    )
  end
end
