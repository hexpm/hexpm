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

  def dependencies(conn, params) do
    access_package(conn, params, fn package, repositories ->
      releases = Releases.all(package)
      current_release = current_release(releases)

      dependants_count =
        Packages.count(repositories, "depends:#{package.repository.name}:#{package.name}")

      render(
        conn,
        "dependencies.html",
        [
          title: "Dependencies of #{package.name}",
          container: "container",
          package: package,
          releases: releases,
          current_release: current_release,
          dependants_count: dependants_count,
          repository_name: package.repository.name
        ] ++ sidebar_assigns(package, releases, current_release)
      )
    end)
  end

  def dependents(conn, params) do
    access_package(conn, params, fn package, repositories ->
      page_param = Hexpm.Utils.safe_int(params["page"]) || 1
      per_page = @packages_per_page
      releases = Releases.all(package)
      current_release = current_release(releases)

      dependants_count =
        Packages.count(repositories, "depends:#{package.repository.name}:#{package.name}")

      page = Hexpm.Utils.safe_page(page_param, dependants_count, per_page)

      dependants =
        Packages.search(
          repositories,
          page,
          per_page,
          "depends:#{package.repository.name}:#{package.name}",
          :recent_downloads,
          nil
        )
        |> Packages.attach_latest_releases()

      dependants_downloads = Downloads.packages_all_views(dependants)

      render(
        conn,
        "dependents.html",
        [
          title: "Packages depending on #{package.name}",
          container: "container",
          package: package,
          releases: releases,
          current_release: current_release,
          dependants: dependants,
          dependants_count: dependants_count,
          dependants_downloads: dependants_downloads,
          repository_name: package.repository.name,
          page: page,
          per_page: per_page
        ] ++ sidebar_assigns(package, releases, current_release)
      )
    end)
  end

  def versions(conn, params) do
    access_package(conn, params, fn package, repositories ->
      releases = Releases.all(package)
      current_release = current_release(releases)

      dependants_count =
        Packages.count(repositories, "depends:#{package.repository.name}:#{package.name}")

      render(
        conn,
        "versions.html",
        [
          title: "#{package.name} versions",
          container: "container",
          package: package,
          releases: releases,
          current_release: current_release,
          dependants_count: dependants_count,
          repository_name: package.repository.name
        ] ++ sidebar_assigns(package, releases, current_release)
      )
    end)
  end

  def audit_logs(conn, params) do
    access_package(conn, params, fn package, repositories ->
      page_param = Hexpm.Utils.safe_int(params["page"]) || 1
      per_page = @audit_logs_per_page
      total_count = AuditLogs.count_by(package)
      page = Hexpm.Utils.safe_page(page_param, total_count, per_page)
      audit_logs = AuditLogs.all_by(package, page, per_page)
      releases = Releases.all(package)
      current_release = current_release(releases)

      dependants_count =
        Packages.count(repositories, "depends:#{package.repository.name}:#{package.name}")

      render(
        conn,
        "audit_logs.html",
        [
          title: "Recent Activities for #{package.name}",
          container: "container",
          package: package,
          releases: releases,
          current_release: current_release,
          dependants_count: dependants_count,
          repository_name: package.repository.name,
          audit_logs: audit_logs,
          audit_logs_total_count: total_count,
          page: page,
          per_page: per_page
        ] ++ sidebar_assigns(package, releases, current_release)
      )
    end)
  end

  defp current_release(releases) do
    case Release.latest_version(releases, only_stable: true, unstable_fallback: true) do
      nil -> nil
      release -> Releases.preload(release, [:requirements, :downloads, :publisher])
    end
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
          [docs_html_url: Hexpm.Utils.docs_html_url(repository, package, nil)]

        type == :release and release.has_docs ->
          [docs_html_url: Hexpm.Utils.docs_html_url(repository, package, release)]

        true ->
          [docs_html_url: nil]
      end

    last_download_day =
      Hexpm.Cache.fetch(:last_download_day, &Downloads.last_day/0) || Date.utc_today()

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
        container: "container",
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

  defp sidebar_assigns(package, releases, current_release) do
    repository = package.repository

    latest_release_with_docs =
      Release.latest_version(releases,
        only_stable: true,
        unstable_fallback: true,
        with_docs: true
      )

    docs_html_url =
      cond do
        latest_release_with_docs && current_release &&
            current_release.version == latest_release_with_docs.version ->
          Hexpm.Utils.docs_html_url(repository, package, current_release)

        latest_release_with_docs ->
          Hexpm.Utils.docs_html_url(repository, package, nil)

        true ->
          nil
      end

    last_download_day =
      Hexpm.Cache.fetch(:last_download_day, &Downloads.last_day/0) || Date.utc_today()

    start_download_day = Date.add(last_download_day, -30)
    package_downloads = Downloads.package(package)

    graph_source = current_release || package

    graph_downloads =
      Downloads.for_period(graph_source, :day, downloads_after: start_download_day)

    graph_downloads = Map.new(graph_downloads, &{Date.from_iso8601!(&1.day), &1})

    daily_graph =
      Enum.map(Date.range(start_download_day, last_download_day), fn day ->
        if dl = graph_downloads[day], do: dl.downloads, else: 0
      end)

    owners = Owners.all(package, user: [:emails, :organization])

    [
      docs_html_url: docs_html_url,
      downloads: package_downloads,
      daily_graph: daily_graph,
      owners: owners
    ]
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
end
