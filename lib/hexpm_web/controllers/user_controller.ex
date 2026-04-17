defmodule HexpmWeb.UserController do
  use HexpmWeb, :controller

  alias Hexpm.Repository.Downloads

  @packages_per_page 20
  @y_axis_positions [194, 154, 114, 74, 34]

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
      container: "flex-1 flex flex-col",
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

  def stats(conn, %{"username" => username} = params) do
    sort_by = params["sort"] || "downloads"

    with user when is_struct(user) <-
           Users.get_by_username(username, [
             :emails,
             :organization,
             owned_packages: [:repository, :downloads]
           ]) do
      all_packages =
        user
        |> Packages.accessible_user_owned_packages(conn.assigns.current_user)
        |> Packages.attach_latest_releases()

      package_downloads = Downloads.packages_all_views(all_packages)
      package_graphs = build_package_graphs(all_packages, package_downloads, sort_by)

      render(conn, "stats.html",
        title: "#{user.username} — Stats",
        container: "flex-1 flex flex-col",
        gravatar_email: User.email(user, :gravatar),
        package_graphs: package_graphs,
        public_email: User.email(user, :public),
        sort_by: sort_by,
        total_downloads: sum_all_downloads(package_downloads),
        total_packages: length(all_packages),
        user: user
      )
    else
      _ -> not_found(conn)
    end
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

  defp sum_all_downloads(package_downloads) do
    Enum.reduce(package_downloads, 0, fn {_id, d}, acc -> acc + Map.get(d, "all", 0) end)
  end

  defp build_package_graphs(packages, package_downloads, sort_by) do
    last_day =
      Hexpm.Cache.fetch(:last_download_day, &Downloads.last_day/0) || Date.utc_today()

    start_day = Date.add(last_day, -30)

    period_downloads =
      Downloads.for_packages_period(packages, :day, downloads_after: start_day)

    packages
    |> Enum.map(&build_graph_entry(&1, period_downloads, package_downloads, start_day, last_day))
    |> sort_graphs(sort_by)
  end

  defp build_graph_entry(package, period_downloads, package_downloads, start_day, last_day) do
    graph_downloads =
      period_downloads
      |> Map.get(package.id, [])
      |> Map.new(&{Date.from_iso8601!(&1.day), &1})

    daily =
      Enum.map(Date.range(start_day, last_day), fn day ->
        if dl = graph_downloads[day], do: dl.downloads, else: 0
      end)

    {labels, graph_points, graph_fill} = HexpmWeb.ViewHelpers.time_series_graph(daily)

    %{
      package: package,
      graph_points: graph_points,
      graph_fill: graph_fill,
      y_axis_labels: Enum.zip(labels, @y_axis_positions),
      all_downloads: get_in(package_downloads, [package.id, "all"]) || 0,
      week_downloads: get_in(package_downloads, [package.id, "week"]) || 0,
      day_downloads: get_in(package_downloads, [package.id, "day"]) || 0
    }
  end

  defp sort_graphs(graphs, "name"), do: Enum.sort_by(graphs, & &1.package.name)
  defp sort_graphs(graphs, _), do: Enum.sort_by(graphs, & &1.all_downloads, :desc)
end
