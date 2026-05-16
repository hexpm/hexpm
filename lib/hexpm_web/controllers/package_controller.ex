defmodule HexpmWeb.PackageController do
  use HexpmWeb, :controller

  alias Hexpm.Security.Advisories

  @packages_per_page 30
  @versions_per_page 100
  @activity_per_page 100
  @audit_logs_preview_count 10

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
    params = fixup_params(params)

    access_package(conn, params, fn package, repositories ->
      releases = Releases.all(package)

      release =
        if version = params["version"] do
          matching_release(releases, version)
        else
          current_release(releases)
        end

      if release do
        release = preload_release(release)
        dependants_count = Packages.count_dependants(repositories, package)

        render(
          conn,
          "dependencies.html",
          [
            title: "Dependencies of #{package.name}",
            container: "container",
            package: package,
            releases: releases,
            current_release: release,
            version_pinned?: params["version"] != nil,
            dependants_count: dependants_count,
            repository_name: package.repository.name
          ] ++ sidebar_assigns(conn, package, releases, release)
        )
      else
        not_found(conn)
      end
    end)
  end

  def dependents(conn, params) do
    access_package(conn, params, fn package, repositories ->
      page_param = Hexpm.Utils.safe_int(params["page"]) || 1
      per_page = @packages_per_page
      releases = Releases.all(package)
      current_release = current_release(releases)

      dependants_count = Packages.count_dependants(repositories, package)

      page = Hexpm.Utils.safe_page(page_param, dependants_count, per_page)

      dependants =
        Packages.dependants(
          repositories,
          package,
          page,
          per_page,
          :recent_downloads
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
        ] ++ sidebar_assigns(conn, package, releases, current_release)
      )
    end)
  end

  def versions(conn, params) do
    access_package(conn, params, fn package, repositories ->
      releases = Releases.all(package)
      page_param = Hexpm.Utils.safe_int(params["page"]) || 1
      per_page = @versions_per_page
      total_count = Enum.count(releases)
      page = Hexpm.Utils.safe_page(page_param, total_count, per_page)
      current_release = current_release(releases)
      paginated_releases = paginate_list(releases, page, per_page)

      dependants_count = Packages.count_dependants(repositories, package)

      render(
        conn,
        "versions.html",
        [
          title: "#{package.name} versions",
          container: "container",
          package: package,
          releases: paginated_releases,
          all_versions: Enum.map(releases, & &1.version),
          current_release: current_release,
          dependants_count: dependants_count,
          repository_name: package.repository.name,
          page: page,
          per_page: per_page,
          releases_total_count: total_count
        ] ++ sidebar_assigns(conn, package, releases, current_release)
      )
    end)
  end

  def advisories(conn, params) do
    access_package(conn, params, fn package, _repositories ->
      releases = Releases.all(package)
      current_release = current_release(releases)

      advisories =
        package
        |> Advisories.all()
        |> Advisories.group_for_display()

      dependants_count =
        Packages.count(
          [package.repository],
          "depends:#{package.repository.name}:#{package.name}"
        )

      render(
        conn,
        "advisories.html",
        [
          title: "Security Advisories for #{package.name}",
          container: "container",
          package: package,
          releases: releases,
          current_release: current_release,
          advisories: advisories,
          dependants_count: dependants_count,
          versions_count: Enum.count(releases),
          repository_name: package.repository.name
        ] ++ sidebar_assigns(conn, package, releases, current_release)
      )
    end)
  end

  def audit_logs(conn, params) do
    access_package(conn, params, fn package, repositories ->
      page_param = Hexpm.Utils.safe_int(params["page"]) || 1
      per_page = @activity_per_page
      total_count = AuditLogs.count_by(package)
      page = Hexpm.Utils.safe_page(page_param, total_count, per_page)
      audit_logs = AuditLogs.all_by(package, page, per_page)
      releases = Releases.all(package)
      current_release = current_release(releases)

      dependants_count = Packages.count_dependants(repositories, package)

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
        ] ++ sidebar_assigns(conn, package, releases, current_release)
      )
    end)
  end

  defp current_release(releases) do
    case Release.latest_version(releases, only_stable: true, unstable_fallback: true) do
      nil -> nil
      release -> preload_release(release)
    end
  end

  defp preload_release(release) do
    Releases.preload(release, [:requirements, :downloads, :publisher])
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

  defp matching_release(releases, version) do
    Enum.find(releases, &(to_string(&1.version) == version))
  end

  defp package(conn, repositories, package, releases, release, type) do
    repository = package.repository

    release =
      Releases.preload(release, [:requirements, :downloads, :publisher, :security_advisories])

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

    graph_release =
      case type do
        :package -> nil
        :release -> release
      end

    graph_downloads =
      Downloads.for_period(graph_release || package, :day, downloads_after: start_download_day)

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
      Packages.dependants(repositories, package, 1, 20, :recent_downloads, [:name, :repository_id])

    dependants_count = Packages.count_dependants(repositories, package)

    audit_logs = AuditLogs.all_by(package, 1, @audit_logs_preview_count)

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
        all_releases: releases,
        current_release: release,
        version_pinned?: type == :release,
        downloads: downloads,
        owners: owners,
        dependants: dependants,
        dependants_count: dependants_count,
        versions_count: Enum.count(releases),
        audit_logs: audit_logs,
        daily_graph: daily_graph,
        graph_release: graph_release,
        type: type,
        current_user: conn.assigns.current_user
      ] ++ docs_assigns
    )
  end

  defp sidebar_assigns(conn, package, releases, current_release) do
    sidebar_assigns(package, releases, current_release)
    |> Keyword.put(:current_user, conn.assigns.current_user)
  end

  defp sidebar_assigns(package, releases, current_release) do
    latest_release_with_docs =
      Release.latest_version(releases,
        only_stable: true,
        unstable_fallback: true,
        with_docs: true
      )

    docs_html_url =
      Hexpm.Utils.current_docs_html_url(package, current_release, latest_release_with_docs)

    last_download_day =
      Hexpm.Cache.fetch(:last_download_day, &Downloads.last_day/0) || Date.utc_today()

    start_download_day = Date.add(last_download_day, -30)
    package_downloads = Downloads.package(package)

    graph_downloads =
      Downloads.for_period(package, :day, downloads_after: start_download_day)

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
      owners: owners,
      versions_count: Enum.count(releases),
      all_releases: releases
    ]
  end

  defp paginate_list(list, page, per_page) do
    offset = (page - 1) * per_page
    Enum.slice(list, offset, per_page)
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
