defmodule HexpmWeb.PackageLayoutAssigns do
  @moduledoc """
  Single source of truth for the assigns that
  `HexpmWeb.Components.PackageLayout` needs.

  Every controller action that renders a template containing
  `<.package_layout {@package_layout} ...>` MUST build its assigns via
  `for_package/3`. The returned keyword list contains the shared header,
  version dropdown, and sidebar data, plus a `:package_layout` map that
  the template spreads into the component.

  Adding a new package tab? Call `for_package/3` and merge its result
  into your render assigns — nothing else to remember.

  Adding a new field the package layout depends on? Add it here once,
  and every tab gets it.
  """

  alias Hexpm.Accounts.Users
  alias Hexpm.Repository.{Downloads, Owners, Packages, Release, Releases}

  @doc """
  Builds the layout assigns for `package`.

  Options:

    * `:releases` — preloaded list of releases (avoids an extra DB query)
    * `:current_release` — override the default current release (used by
      version-pinned routes like `/packages/:name/:version`)
    * `:graph_release` — release to scope the downloads chart to; when
      `nil` the chart shows package-wide downloads
    * `:docs_html_url` — override the computed docs URL when the page
      has special docs link logic (e.g. the package show page)
    * `:sidebar?` — load download and chart data for the package sidebar;
      defaults to `true`
  """
  def for_package(conn_or_user, package, opts \\ []) do
    current_user = current_user(conn_or_user)
    releases = opts[:releases] || Releases.all(package)
    current_release = resolve_current_release(opts[:current_release], releases)
    graph_release = opts[:graph_release]
    sidebar? = Keyword.get(opts, :sidebar?, true)

    repositories =
      current_user
      |> Users.all_organizations()
      |> Enum.map(& &1.repository)

    docs_html_url =
      Keyword.get_lazy(opts, :docs_html_url, fn ->
        latest_release_with_docs =
          Release.latest_version(releases,
            only_stable: true,
            unstable_fallback: true,
            with_docs: true
          )

        Hexpm.Utils.current_docs_html_url(package, current_release, latest_release_with_docs)
      end)

    layout = [
      package: package,
      current_user: current_user,
      repository_name: package.repository.name,
      all_releases: releases,
      current_release: current_release,
      versions_count: Enum.count(releases),
      owners: Owners.all(package, user: [:emails, :organization]),
      downloads: if(sidebar?, do: Downloads.package(package), else: %{}),
      daily_graph: if(sidebar?, do: daily_graph(graph_release || package), else: []),
      graph_release: graph_release,
      docs_html_url: docs_html_url,
      dependants_count: Packages.count_dependants(repositories, package)
    ]

    [{:package_layout, Map.new(layout)} | layout]
  end

  defp current_user(%Plug.Conn{} = conn), do: conn.assigns.current_user
  defp current_user(user), do: user

  defp resolve_current_release(nil, releases) do
    case Release.latest_version(releases, only_stable: true, unstable_fallback: true) do
      nil -> nil
      release -> Releases.preload(release, [:requirements, :downloads, :publisher])
    end
  end

  defp resolve_current_release(release, _releases), do: release

  defp daily_graph(package_or_release) do
    last_day = Hexpm.Cache.fetch(:last_download_day, &Downloads.last_day/0) || Date.utc_today()
    start_day = Date.add(last_day, -30)

    by_day =
      package_or_release
      |> Downloads.for_period(:day, downloads_after: start_day)
      |> Map.new(&{Date.from_iso8601!(&1.day), &1})

    Enum.map(Date.range(start_day, last_day), fn day ->
      if dl = by_day[day], do: dl.downloads, else: 0
    end)
  end
end
