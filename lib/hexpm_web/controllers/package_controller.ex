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
    packages = fetch_packages(repositories, page, @packages_per_page, filter, sort)
    downloads = Packages.packages_downloads_with_all_views(packages)
    exact_match = exact_match(repositories, search)

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

  defp package(conn, repositories, package, releases, release, type) do
    repository = package.repository
    release = Releases.preload(release, [:requirements, :downloads, :publisher])

    latest_release_with_docs =
      Release.latest_version(releases, only_stable: true, unstable_fallback: true, with_docs: true)

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

    downloads = Packages.package_downloads(package)

    graph_downloads =
      case type do
        :package -> Packages.downloads_for_last_n_days(package.id, 31)
        :release -> Releases.downloads_for_last_n_days(release.id, 31)
      end

    daily_graph =
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
        canonical_url: Routes.package_url(conn, :show, package),
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
    packages = Packages.search(repositories, page, packages_per_page, search, sort, nil)
    Packages.attach_versions(packages)
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
