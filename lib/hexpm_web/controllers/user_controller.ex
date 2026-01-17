defmodule HexpmWeb.UserController do
  use HexpmWeb, :controller

  @packages_per_page 20

  def show(conn, %{"username" => username} = params) do
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
          show_user(conn, user, params)
      end
    else
      not_found(conn)
    end
  end

  defp show_user(conn, user, params) do
    sort_by = Map.get(params, "sort", "popular")
    page = Hexpm.Utils.safe_int(params["page"]) || 1

    all_packages =
      Packages.accessible_user_owned_packages(user, conn.assigns.current_user)
      |> Packages.attach_latest_releases()

    downloads = Downloads.packages_all_views(all_packages)

    total_downloads =
      Enum.reduce(downloads, 0, fn {_id, d}, acc -> acc + Map.get(d, "all", 0) end)

    # Sort all packages
    sorted_packages = sort_packages(all_packages, downloads, sort_by)

    # Paginate the sorted packages
    total_count = length(sorted_packages)
    paginated_packages = paginate_list(sorted_packages, page, @packages_per_page)

    public_email = User.email(user, :public)
    gravatar_email = User.email(user, :gravatar)

    render(
      conn,
      "show.html",
      title: user.username,
      container: "tw:flex-1 tw:flex tw:flex-col",
      user: user,
      packages: paginated_packages,
      downloads: downloads,
      total_downloads: total_downloads,
      total_count: total_count,
      public_email: public_email,
      gravatar_email: gravatar_email,
      sort_by: sort_by,
      page: page,
      per_page: @packages_per_page
    )
  end

  defp sort_packages(packages, downloads, "downloads") do
    Enum.sort_by(packages, fn pkg ->
      -(get_in(downloads, [pkg.id, "all"]) || 0)
    end)
  end

  defp sort_packages(packages, _downloads, "newest") do
    Enum.sort_by(packages, & &1.inserted_at, {:desc, DateTime})
  end

  defp sort_packages(packages, downloads, _popular) do
    # Most popular - sort by downloads (same as "downloads" for now)
    Enum.sort_by(packages, fn pkg ->
      -(get_in(downloads, [pkg.id, "all"]) || 0)
    end)
  end

  defp paginate_list(list, page, per_page) do
    offset = (page - 1) * per_page
    Enum.slice(list, offset, per_page)
  end
end
