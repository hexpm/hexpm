defmodule HexpmWeb.PackageController do
  use HexpmWeb, :controller

  @packages_per_page 30
  @audit_logs_per_page 10
  @sort_params ~w(name recent_downloads total_downloads inserted_at updated_at)
  @letters for letter <- ?A..?Z, do: <<letter>>

  def index(conn, params) do
    letter = Hexpm.Utils.parse_search(params["letter"])
    search = Hexpm.Utils.parse_search(params["search"])

    filter =
      cond do
        letter ->
          {:letter, letter}

        search ->
          search

        true ->
          nil
      end

    organizations = Users.all_organizations(conn.assigns.current_user)
    repositories = Enum.map(organizations, & &1.repository)
    sort = sort(params["sort"])
    page_param = Hexpm.Utils.safe_int(params["page"]) || 1
    package_count = Packages.count(repositories, filter)
    page = Hexpm.Utils.safe_page(page_param, package_count, @packages_per_page)
    exact_match = exact_match(repositories, search)
    all_matches = fetch_packages(repositories, page, @packages_per_page, filter, sort)
    downloads = Downloads.packages_all_views(Enum.reject([exact_match | all_matches], &is_nil/1))
    packages = Packages.diff(all_matches, exact_match)

    maybe_log_search(search, package_count)

    render(
      conn,
      "index.html",
      title: "Packages",
      container: "container",
      per_page: @packages_per_page,
      search: search,
      letter: letter,
      sort: sort,
      package_count: package_count,
      page: page,
      packages: packages,
      letters: @letters,
      downloads: downloads,
      exact_match: exact_match
    )
  end

  def show(conn, params) do
    # TODO: Show flash if private package and organization does not have active billing

    params = fixup_params(params)

    access_package(conn, params, fn package, repositories ->
      releases = Releases.all(package)

      {release, type} =
        if version = params["version"] do
          {matching_release(releases, version), :release}
        else
          {Release.latest_version(releases, only_stable: true, unstable_fallback: true), :package}
        end

      if release do
        package(conn, repositories, package, releases, release, type)
      else
        not_found(conn)
      end
    end)
  end

  def audit_logs(conn, params) do
    access_package(conn, params, fn package, _ ->
      page = Hexpm.Utils.safe_int(params["page"]) || 1
      per_page = 100
      audit_logs = AuditLogs.all_by(package, page, per_page)
      total_count = AuditLogs.count_by(package)

      render(conn, "audit_logs.html",
        title: "Recent Activities for #{package.name}",
        container: "container package-view",
        package: package,
        audit_logs: audit_logs,
        audit_logs_total_count: total_count,
        page: page,
        per_page: per_page
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

  defp package(conn, repositories, package, releases, release, type) do
    repository = package.repository
    release = Releases.preload(release, [:requirements, :downloads, :publisher])

    latest_release_with_docs =
      Release.latest_version(releases,
        only_stable: true,
        unstable_fallback: true,
        with_docs: true
      )

    docs_assigns =
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

    last_download_day = Downloads.last_day() || Date.utc_today()
    start_download_day = Date.add(last_download_day, -30)
    downloads = Downloads.package(package)

    graph_downloads_for =
      case type do
        :package -> package
        :release -> release
      end

    graph_downloads =
      Downloads.for_period(graph_downloads_for, :day, downloads_after: start_download_day)

    graph_downloads = Map.new(graph_downloads, &{Date.from_iso8601!(&1.day), &1})

    daily_graph =
      Enum.map(Date.range(start_download_day, last_download_day), fn day ->
        if download = graph_downloads[day] do
          download.downloads
        else
          0
        end
      end)

    owners = Owners.all(package, user: [:emails, :organization])

    dependants =
      Packages.search(
        repositories,
        1,
        20,
        "depends:#{repository.name}:#{package.name}",
        :recent_downloads,
        [:name, :repository_id]
      )

    dependants_count = Packages.count(repositories, "depends:#{repository.name}:#{package.name}")

    audit_logs = AuditLogs.all_by(package, 1, @audit_logs_per_page)

    render(
      conn,
      "show.html",
      [
        title: package.name,
        description: package.meta.description,
        container: "container package-view",
        canonical_url: ~p"/packages/#{package}",
        package: package,
        repository_name: repository.name,
        releases: releases,
        current_release: release,
        downloads: downloads,
        owners: owners,
        dependants: dependants,
        dependants_count: dependants_count,
        audit_logs: audit_logs,
        daily_graph: daily_graph,
        type: type
      ] ++ docs_assigns
    )
  end

  defp fetch_packages(repositories, page, packages_per_page, search, sort) do
    repositories
    |> Packages.search(page, packages_per_page, search, sort, nil)
    |> Packages.attach_latest_releases()
  end

  defp exact_match(_organizations, nil) do
    nil
  end

  defp exact_match(repositories, search) do
    search
    |> String.replace(" ", "_")
    |> String.split("/", parts: 2)
    |> case do
      [repository, package] ->
        if repository in Enum.map(repositories, & &1.name) do
          Packages.get(repository, package)
        end

      [term] ->
        try do
          Packages.get(repositories, term)
        rescue
          Ecto.MultipleResultsError ->
            nil
        end
    end
    |> case do
      nil ->
        nil

      package ->
        [package] = Packages.attach_latest_releases([package])
        package
    end
  end

  defp fixup_params(%{"name" => name, "version" => version} = params) do
    case Version.parse(version) do
      {:ok, _} ->
        params

      :error ->
        params
        |> Map.put("repository", name)
        |> Map.put("name", version)
        |> Map.delete("version")
    end
  end

  defp fixup_params(params) do
    params
  end

  defp maybe_log_search(search, 0) do
    Hexpm.Repository.PackageSearches.add_or_increment(%{"term" => search})
  end

  defp maybe_log_search(_search, _package_count), do: :noop
end
