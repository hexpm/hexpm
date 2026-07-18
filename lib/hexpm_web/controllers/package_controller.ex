defmodule HexpmWeb.PackageController do
  use HexpmWeb, :controller

  alias Hexpm.Security.Advisories
  alias HexpmWeb.PackageLayoutAssigns

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

    access_package(conn, params, fn package, _repositories ->
      releases = Releases.all(package)

      release =
        if version = params["version"] do
          matching_release(releases, version)
        else
          current_release(releases)
        end

      if release do
        release = preload_release(release)

        render(
          conn,
          "dependencies.html",
          [
            title: "Dependencies of #{package.name}",
            container: "container",
            releases: releases,
            version_pinned?: params["version"] != nil
          ] ++
            PackageLayoutAssigns.for_package(conn, package,
              releases: releases,
              current_release: release
            )
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
        repositories
        |> Packages.dependants(package, page, per_page, :recent_downloads)
        |> Packages.attach_latest_releases()

      dependants_downloads = Downloads.packages_all_views(dependants)
      dependants_requirements = Packages.dependant_requirements(dependants, package)

      render(
        conn,
        "dependents.html",
        [
          title: "Packages depending on #{package.name}",
          container: "container",
          releases: releases,
          dependants: dependants,
          dependants_downloads: dependants_downloads,
          dependants_requirements: dependants_requirements,
          page: page,
          per_page: per_page
        ] ++
          PackageLayoutAssigns.for_package(conn, package,
            releases: releases,
            current_release: current_release
          )
      )
    end)
  end

  def versions(conn, params) do
    access_package(conn, params, fn package, _repositories ->
      releases = Releases.all(package)
      page_param = Hexpm.Utils.safe_int(params["page"]) || 1
      per_page = @versions_per_page
      total_count = Enum.count(releases)
      page = Hexpm.Utils.safe_page(page_param, total_count, per_page)
      current_release = current_release(releases)
      paginated_releases = paginate_list(releases, page, per_page)

      render(
        conn,
        "versions.html",
        [
          title: "#{package.name} versions",
          container: "container",
          releases: paginated_releases,
          all_versions: Enum.map(releases, & &1.version),
          page: page,
          per_page: per_page,
          releases_total_count: total_count
        ] ++
          PackageLayoutAssigns.for_package(conn, package,
            releases: releases,
            current_release: current_release
          )
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

      render(
        conn,
        "advisories.html",
        [
          title: "Security Advisories for #{package.name}",
          container: "container",
          releases: releases,
          advisories: advisories
        ] ++
          PackageLayoutAssigns.for_package(conn, package,
            releases: releases,
            current_release: current_release
          )
      )
    end)
  end

  def audit_logs(conn, params) do
    access_package(conn, params, fn package, _repositories ->
      page_param = Hexpm.Utils.safe_int(params["page"]) || 1
      per_page = @activity_per_page
      total_count = AuditLogs.count_by(package)
      page = Hexpm.Utils.safe_page(page_param, total_count, per_page)
      audit_logs = AuditLogs.all_by(package, page, per_page)
      releases = Releases.all(package)
      current_release = current_release(releases)

      render(
        conn,
        "audit_logs.html",
        [
          title: "Recent Activities for #{package.name}",
          container: "container",
          releases: releases,
          audit_logs: audit_logs,
          audit_logs_total_count: total_count,
          page: page,
          per_page: per_page
        ] ++
          PackageLayoutAssigns.for_package(conn, package,
            releases: releases,
            current_release: current_release
          )
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

    # Should have access even though organization does not have active billing
    case HexpmWeb.RepositoryAccess.fetch_package(conn.assigns.current_user, repository, name) do
      {:ok, package} ->
        organizations = Users.all_organizations(conn.assigns.current_user)
        fun.(package, Enum.map(organizations, & &1.repository))

      :error ->
        not_found(conn)
    end
  end

  defp matching_release(releases, version) do
    Enum.find(releases, &(to_string(&1.version) == version))
  end

  defp package(conn, repositories, package, releases, release, type) do
    release =
      Releases.preload(release, [:requirements, :downloads, :publisher, :security_advisories])

    graph_release =
      case type do
        :package -> nil
        :release -> release
      end

    dependants =
      Packages.dependants(repositories, package, 1, 20, :recent_downloads, [:name, :repository_id])

    audit_logs = AuditLogs.all_by(package, 1, @audit_logs_preview_count)

    render(
      conn,
      "show.html",
      [
        title: package.name,
        description: package.meta.description,
        container: "container",
        canonical_url: ~p"/packages/#{package}",
        releases: releases,
        version_pinned?: type == :release,
        dependants: dependants,
        audit_logs: audit_logs,
        type: type
      ] ++
        PackageLayoutAssigns.for_package(conn, package,
          releases: releases,
          current_release: release,
          graph_release: graph_release,
          docs_html_url: show_docs_html_url(package, type, release, releases)
        )
    )
  end

  defp show_docs_html_url(package, :package, _release, releases) do
    latest_release_with_docs =
      Release.latest_version(releases,
        only_stable: true,
        unstable_fallback: true,
        with_docs: true
      )

    latest_release_with_docs &&
      Hexpm.Utils.docs_html_url(package.repository, package, nil)
  end

  defp show_docs_html_url(package, :release, %{has_docs: true} = release, _releases),
    do: Hexpm.Utils.docs_html_url(package.repository, package, release)

  defp show_docs_html_url(_package, _type, _release, _releases), do: nil

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
