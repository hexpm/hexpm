defmodule HexpmWeb.PackageController do
  use HexpmWeb, :controller

  plug :fixup_params
  plug :redirect_hexpm
  plug :put_layout, {HexpmWeb.PackageView, "layout.html"}

  @packages_per_page 30
  @audit_logs_per_page 10
  @sort_params ~w(name recent_downloads total_downloads inserted_at updated_at recently_published)

  def index(conn, params) do
    search = Hexpm.Utils.parse_search(params["search"])
    organizations = Users.all_organizations(conn.assigns.current_user)
    repositories = Enum.map(organizations, & &1.repository)
    sort = sort(params["sort"])
    page_param = Hexpm.Utils.safe_int(params["page"]) || 1
    package_count = Packages.count(repositories, search)
    page = Hexpm.Utils.safe_page(page_param, package_count, @packages_per_page)
    packages = fetch_packages(repositories, page, @packages_per_page, search, sort)
    downloads = Packages.packages_downloads_with_all_views(packages)
    exact_match = exact_match(repositories, search)

    render(
      conn,
      "index.html",
      title: "Packages",
      nav_page: :packages,
      per_page: @packages_per_page,
      search: search,
      sort: sort,
      package_count: package_count,
      page: page,
      packages: packages,
      downloads: downloads,
      exact_match: exact_match,
      hide_header_search: true
    )
  end

  def show(conn, params) do
    # TODO: Show flash if private package and organization does not have active billing

    access_package(conn, params, fn package, repositories ->
      releases = Releases.all(package)
      {release, type} = release_type(releases, params)

      if release do
        render(
          conn,
          "show.html",
          package_assigns(conn, repositories, package, releases, release, type)
        )
      else
        not_found(conn)
      end
    end)
  end

  def readme(conn, params) do
    access_package(conn, params, fn package, _repositories ->
      conn
      |> put_layout(false)
      |> render("readme.html", readme: Packages.readme(package))
    end)
  end

  def versions(conn, params) do
    access_package(conn, params, fn package, repositories ->
      releases = Releases.all(package)
      {release, type} = release_type(releases, params)

      render(
        conn,
        "versions.html",
        package_assigns(conn, repositories, package, releases, release, type)
      )
    end)
  end

  def activity(conn, params) do
    access_package(conn, params, fn package, _repositories ->
      page = Hexpm.Utils.safe_int(params["page"]) || 1
      per_page = 100
      audit_logs = AuditLogs.all_by(package, page, per_page)
      total_count = AuditLogs.count_by(package)

      render(conn, "activity.html",
        title: package.name,
        nav_page: :packages,
        package: package,
        audit_logs: audit_logs,
        page: page,
        per_page: per_page,
        total_count: total_count
      )
    end)
  end

  defp access_package(conn, params, fun) do
    %{"repository" => repository, "name" => name} = params
    organizations = Users.all_organizations(conn.assigns.current_user)
    repositories = Map.new(organizations, &{&1.repository.name, &1.repository})

    if repository = repositories[repository] do
      package = repository && Packages.get(repository, name)

      # Should have access even though organization does not have active billing
      if package do
        fun.(package, Enum.map(organizations, & &1.repository))
      end
    end || not_found(conn)
  end

  defp sort(nil), do: sort("recent_downloads")
  defp sort("downloads"), do: sort("recent_downloads")
  defp sort(param), do: Hexpm.Utils.safe_to_atom(param, @sort_params)

  defp matching_release(releases, version) do
    Enum.find(releases, &(to_string(&1.version) == version))
  end

  defp package_assigns(conn, repositories, package, releases, release, type) do
    repository = package.repository
    release = Releases.preload(release, [:requirements, :downloads, :publisher])
    owners = Owners.all(package, user: [:emails, :organization])

    [
      title: package.name,
      description: package.meta.description,
      nav_page: :packages,
      canonical_url: Routes.package_url(conn, :show, package),
      package: package,
      release: release,
      releases: releases,
      owners: owners,
      type: type
    ] ++
      docs_assigns(repository, package, release, type, releases) ++
      dependants_assigns(repository, package, repositories)
  end

  defp docs_assigns(repository, package, release, type, releases) do
    latest_release_with_docs =
      Release.latest_version(releases, only_stable: true, unstable_fallback: true, with_docs: true)

    cond do
      type == :package && latest_release_with_docs ->
        [
          docs_html_url: Hexpm.Utils.docs_html_url(repository, package, nil),
          docs_tarball_url:
            Hexpm.Utils.docs_tarball_url(repository, package, latest_release_with_docs)
        ]

      type == :release and release.has_docs ->
        [
          docs_html_url: Hexpm.Utils.docs_html_url(repository, package, release),
          docs_tarball_url: Hexpm.Utils.docs_tarball_url(repository, package, release)
        ]

      true ->
        [docs_html_url: nil, docs_tarball_url: nil]
    end
  end

  defp dependants_assigns(repository, package, repositories) do
    query = depends_query(repository, package)

    dependants =
      Packages.search(
        repositories,
        1,
        20,
        query,
        :recent_downloads,
        [:name, :repository_id]
      )

    dependants_count = Packages.count(repositories, query)

    [dependants: dependants, dependants_count: dependants_count]
  end

  defp depends_query(%Repository{id: 1}, package), do: "depends:#{package.name}"
  defp depends_query(repository, package), do: "depends:#{repository.name}/#{package.name}"

  defp daily_graph(type, release, releases) do
    graph_downloads =
      case type do
        :package -> Releases.downloads_for_last_n_days(Enum.map(releases, & &1.id), 31)
        :release -> Releases.downloads_for_last_n_days(release.id, 31)
      end

    Date.utc_today()
    |> Date.add(-31)
    |> Date.range(Date.add(Date.utc_today(), -1))
    |> Enum.map(fn date ->
      Enum.find(graph_downloads, fn dl -> date == Date.from_iso8601!(dl.day) end)
    end)
    |> Enum.map(fn
      nil -> 0
      %{downloads: dl} -> dl
    end)
  end

  defp fetch_packages(repositories, page, packages_per_page, search, sort) do
    packages = Packages.search(repositories, page, packages_per_page, search, sort, nil)
    Packages.attach_versions(packages)
  end

  defp exact_match(_organizations, nil) do
    nil
  end

  defp exact_match(repositories, search) do
    case String.split(search, "/", parts: 2) do
      [repository, package] ->
        if repository in Enum.map(repositories, & &1.name) do
          Packages.get(repository, package)
        end

      _ ->
        try do
          Packages.get(repositories, search)
        rescue
          Ecto.MultipleResultsError ->
            nil
        end
    end
  end

  defp release_type(releases, params) do
    if version = params["version"] do
      {matching_release(releases, version), :release}
    else
      {Release.latest_version(releases, only_stable: true, unstable_fallback: true), :package}
    end
  end

  defp redirect_hexpm(conn, _opts) do
    if path = redirect_path(conn) do
      conn
      |> redirect(to: path)
      |> halt()

    else
      conn
    end
  end

  defp redirect_path(%Plug.Conn{path_info: ["packages", "hexpm" | rest], query_string: ""}) do
    Path.join(["/packages" | rest])
  end

  defp redirect_path(%Plug.Conn{query_string: ""}) do
    nil
  end

  defp redirect_path(%Plug.Conn{query_string: query_string} = conn) do
    if path = redirect_path(%Plug.Conn{conn | query_string: ""}) do
      path <> "?" <> query_string
    end
  end

  defp fixup_params(conn, _opts) do
    case conn.params do
      %{"name" => name, "version" => version} ->
        case Version.parse(version) do
          {:ok, _} ->
            conn

          :error ->
            put_in(
              conn.params,
              conn.params
              |> Map.put("repository", name)
              |> Map.put("name", version)
              |> Map.delete("version")
            )
        end

      _ ->
        conn
    end
  end
end
