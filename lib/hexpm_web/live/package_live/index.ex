defmodule HexpmWeb.PackageLive.Index do
  use HexpmWeb, :live_view

  import HexpmWeb.PackageView, only: [downloads_for_package: 2]
  import HexpmWeb.PackageLive.FilterSidebar
  import HexpmWeb.ViewIcons, only: [icon: 3]

  alias Hexpm.Repository.Package.SearchQuery

  @packages_per_page 30
  @sort_params ~w(name recent_downloads total_downloads inserted_at updated_at)
  @sort_options [
    {"Recent downloads", "recent_downloads"},
    {"Total downloads", "total_downloads"},
    {"Recently updated", "updated_at"},
    {"Recently created", "inserted_at"},
    {"Name (A–Z)", "name"}
  ]

  @impl true
  def mount(_params, _session, socket) do
    organizations = Users.all_organizations(socket.assigns.current_user)
    repositories = Enum.map(organizations, & &1.repository)

    socket =
      assign(socket,
        title: "Packages",
        container: "container",
        live_search: true,
        per_page: @packages_per_page,
        repositories: repositories,
        sort_options: @sort_options
      )

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    socket = load_results(socket, params)
    # Keep the nav search input in sync with the current search query.
    # SearchSuggestionsLive runs in its own process, so its @term assign
    # doesn't automatically update when the parent push_patches to a new URL
    # (e.g. after the sidebar filter changes). We bridge this via a JS event
    # that the SearchInputSync hook picks up and forwards to the child LiveView.
    {:noreply, push_event(socket, "sync-search", %{value: socket.assigns.search || ""})}
  end

  defp load_results(socket, params) do
    repositories = socket.assigns.repositories
    search = Hexpm.Utils.parse_search(params["search"])

    sort = sort(params["sort"])
    page_param = Hexpm.Utils.safe_int(params["page"]) || 1
    package_count = Packages.count(repositories, search)
    page = Hexpm.Utils.safe_page(page_param, package_count, @packages_per_page)
    exact_match = exact_match(repositories, search)

    all_matches =
      repositories
      |> Packages.search(page, @packages_per_page, search, sort, nil)
      |> Packages.attach_latest_releases()

    downloads =
      Downloads.packages_all_views(Enum.reject([exact_match | all_matches], &is_nil/1))

    packages = Packages.diff(all_matches, exact_match)

    search_query =
      case SearchQuery.parse(search) do
        {:ok, query} -> query
        {:error, _} -> %SearchQuery{}
      end

    assign(socket,
      search: search,
      search_query: search_query,
      sort: sort,
      package_count: package_count,
      page: page,
      packages: packages,
      downloads: downloads,
      exact_match: exact_match
    )
  end

  @impl true
  def render(assigns) do
    ~H"""
    <%!-- Package Index Page --%>
    <div class="bg-white dark:bg-grey-950 min-h-dvh">
      <%!-- Header --%>
      <header class="bg-white dark:bg-grey-950 border-b border-grey-100 dark:border-grey-700 pt-14 pb-6">
        <div class="max-w-7xl mx-auto px-4">
          <h1 class="text-h2 font-bold tracking-[-0.02em] text-grey-900 dark:text-grey-100 m-0">
            Packages
          </h1>
          <p class="mt-2 text-body text-grey-500 dark:text-grey-300">
            Browse and discover packages for the Erlang ecosystem
          </p>
        </div>
      </header>

      <main class="max-w-7xl mx-auto px-4 pt-8 pb-20">
        <%!-- Mobile sticky toolbar --%>
        <div class="md:hidden sticky top-0 z-20 -mx-4 px-4 py-2.5 mb-3 bg-white/95 dark:bg-grey-900/95 backdrop-blur border-b border-grey-100 dark:border-grey-700 flex items-center gap-2">
          <button
            type="button"
            phx-click={open_sheet()}
            class="inline-flex items-center gap-1.5 h-9 px-3 rounded-lg border-[1.5px] border-grey-900 dark:border-grey-100 bg-transparent text-grey-900 dark:text-grey-100 text-small font-medium hover:bg-grey-900 hover:text-white dark:hover:bg-grey-100 dark:hover:text-grey-900 transition-colors"
          >
            {icon(:heroicon, "funnel", width: 14, height: 14)} Filters
            <span
              :if={active_count(@search_query) > 0}
              class="text-tiny font-semibold text-white bg-primary-600 px-1.5 py-px rounded-full tabular-nums leading-[1.45]"
            >
              {active_count(@search_query)}
            </span>
          </button>
          <div class="flex-1"></div>
          <%!-- phx-auto-recover stops reconnects from re-firing sort_change and resetting the page --%>
          <form phx-change="sort_change" phx-auto-recover="ignore" class="inline-flex">
            <label for="sort-select-mobile" class="sr-only">Sort</label>
            <div class="relative">
              <select
                id="sort-select-mobile"
                name="sort"
                class="appearance-none h-9 pl-3 pr-8 text-small font-medium bg-white dark:bg-grey-800 border border-grey-200 dark:border-grey-600 rounded-lg text-grey-600 dark:text-grey-200 cursor-pointer focus:outline-none focus:border-primary-600 focus:ring-[3px] focus:ring-primary-100 dark:focus:ring-primary-900/40 transition-[border-color,box-shadow] duration-150"
              >
                <option
                  :for={{label, value} <- @sort_options}
                  value={value}
                  selected={to_string(@sort) == value}
                >
                  Sort: {label}
                </option>
              </select>
              <div class="absolute right-2.5 top-1/2 -translate-y-1/2 pointer-events-none text-grey-400 dark:text-grey-300">
                {icon(:heroicon, "chevron-down", width: 12, height: 12)}
              </div>
            </div>
          </form>
        </div>

        <%!-- Mobile active filter chips --%>
        <div
          :if={active_count(@search_query) > 0}
          class="md:hidden flex flex-wrap gap-1.5 items-center mb-4"
        >
          <span class="text-tiny font-semibold uppercase tracking-[0.08em] text-grey-400 dark:text-grey-300 mr-1">
            Active
          </span>
          <span
            :for={{label, key, value} <- active_chips(@search_query)}
            class="inline-flex items-center gap-1.5 h-[26px] pl-2.5 pr-1.5 text-caption font-medium bg-primary-50 dark:bg-primary-900/30 border border-primary-100 dark:border-primary-800 text-primary-700 dark:text-primary-200 rounded-full"
          >
            <span class="opacity-65">{label}:</span> {value}
            <button
              type="button"
              aria-label={"Remove #{label} filter"}
              phx-click="remove_filter"
              phx-value-key={key}
              class="w-4 h-4 rounded-full inline-flex items-center justify-center hover:bg-primary-100 dark:hover:bg-primary-800 transition-colors"
            >
              {icon(:heroicon, "x-mark", width: 10, height: 10)}
            </button>
          </span>
        </div>

        <div class="md:grid md:grid-cols-[264px_1fr] md:gap-8">
          <%!-- Desktop filter sidebar --%>
          <.sidebar query={@search_query} />

          <%!-- Results column --%>
          <div class="min-w-0">
            <%!-- Exact Match Section --%>
            <div
              :if={@exact_match}
              class="mb-6 bg-green-50 dark:bg-green-900/20 border border-green-200 dark:border-green-800 rounded-xl p-6"
            >
              <div class="flex items-center gap-2 mb-4">
                {icon(:heroicon, "check-circle", class: "size-5 text-green-600")}
                <h3 class="text-green-900 dark:text-green-200 font-semibold text-lg">
                  Exact Match
                </h3>
              </div>
              <ul class="bg-white dark:bg-grey-800 rounded-lg overflow-hidden divide-y divide-grey-100 dark:divide-grey-700">
                {HexpmWeb.PackageView.render("_package.html",
                  exact_match?: true,
                  package: @exact_match,
                  package_downloads: downloads_for_package(@exact_match, @downloads),
                  view: @sort
                )}
              </ul>
            </div>

            <%!-- No Results --%>
            <div
              :if={!@exact_match and @packages == []}
              class="bg-grey-50 dark:bg-grey-800 rounded-xl p-12 text-center"
            >
              {icon(:heroicon, "magnifying-glass", class: "mx-auto size-16 text-grey-300 mb-4")}
              <h3 class="text-grey-900 dark:text-grey-100 text-2xl font-semibold mb-2">
                No Results Found
              </h3>
              <p class="text-grey-600 dark:text-grey-300">
                Try adjusting your search
              </p>
            </div>

            <%!-- Package list --%>
            <div :if={@packages != []}>
              <%!-- Desktop results header with sort --%>
              <div class="hidden md:flex items-end justify-between gap-6 mb-4">
                <div>
                  <h2 class="text-[28px] leading-tight font-bold tracking-[-0.01em] text-grey-900 dark:text-grey-100 m-0">
                    {if @exact_match, do: "Search Results", else: "All Packages"}
                  </h2>
                  <div class="text-small text-grey-500 dark:text-grey-300 mt-1.5">
                    <strong class="text-grey-700 dark:text-grey-100 font-semibold tabular-nums">
                      {ViewHelpers.human_number_space(@package_count)}
                    </strong>
                    {if @package_count == 1, do: "package", else: "packages"} found <% total_pages =
                      max(1, ceil(@package_count / @per_page)) %>
                    <span
                      :if={total_pages > 1}
                      class="inline-block w-[3px] h-[3px] rounded-full bg-grey-300 dark:bg-grey-500 align-middle mx-2"
                    ></span>
                    <span :if={total_pages > 1}>
                      Page {@page} of {total_pages}
                    </span>
                  </div>
                </div>
                <div class="text-right shrink-0">
                  <label
                    for="sort-select"
                    class="block text-tiny font-semibold uppercase tracking-[0.08em] text-grey-400 dark:text-grey-300 mb-1.5"
                  >
                    Sort by
                  </label>
                  <%!-- phx-auto-recover stops reconnects from re-firing sort_change and resetting the page --%>
                  <form phx-change="sort_change" phx-auto-recover="ignore">
                    <div class="relative min-w-[200px]">
                      <select
                        id="sort-select"
                        name="sort"
                        class="w-full h-9 pl-3 pr-8 text-small bg-white dark:bg-grey-800 border border-grey-200 dark:border-grey-600 rounded-lg text-grey-700 dark:text-grey-100 cursor-pointer appearance-none focus:outline-none focus:border-primary-600 focus:ring-[3px] focus:ring-primary-100 dark:focus:ring-primary-900/40 transition-[border-color,box-shadow] duration-150"
                      >
                        <option
                          :for={{label, value} <- @sort_options}
                          value={value}
                          selected={to_string(@sort) == value}
                        >
                          {label}
                        </option>
                      </select>
                      <div class="absolute right-2.5 top-1/2 -translate-y-1/2 pointer-events-none text-grey-400 dark:text-grey-300">
                        {icon(:heroicon, "chevron-down", width: 14, height: 14)}
                      </div>
                    </div>
                  </form>
                </div>
              </div>

              <%!-- Mobile results header --%>
              <div class="md:hidden flex items-baseline justify-between mb-2 px-1">
                <h2 class="text-[17px] font-bold text-grey-900 dark:text-grey-100 m-0">
                  {if @exact_match, do: "Search Results", else: "All Packages"}
                </h2>
                <span class="text-caption text-grey-400 dark:text-grey-300 tabular-nums">
                  <strong class="text-grey-700 dark:text-grey-100 font-semibold">
                    {ViewHelpers.human_number_space(@package_count)}
                  </strong>
                  found
                </span>
              </div>

              <%!-- Package list --%>
              <div class="bg-white dark:bg-grey-800 md:border md:border-grey-100 dark:md:border-grey-700 md:rounded-xl overflow-hidden">
                <ul class="divide-y divide-grey-100 dark:divide-grey-700">
                  <%= for package <- @packages do %>
                    {HexpmWeb.PackageView.render("_package.html",
                      exact_match?: false,
                      package: package,
                      package_downloads: downloads_for_package(package, @downloads),
                      view: @sort
                    )}
                  <% end %>
                </ul>
              </div>

              <%!-- Pagination --%>
              <div class="mt-8">
                {HexpmWeb.SharedView.render(
                  "_pagination.html",
                  items: @packages,
                  page: @page,
                  total_count: @package_count,
                  per_page: @per_page,
                  unit: "package",
                  units: "packages",
                  path_fn: &~p"/packages?#{ViewHelpers.params(&1, search: @search, sort: @sort)}"
                )}
              </div>
            </div>
          </div>
        </div>
      </main>

      <%!-- Mobile filter bottom sheet --%>
      <.mobile_sheet query={@search_query} />
    </div>
    """
  end

  @impl true
  def handle_event("filter_change", params, socket) do
    build_tool = nil_if_empty(params["build_tool"])
    depends = nil_if_empty(params["depends"])

    updated_after =
      case params["updated_after"] do
        nil -> nil
        "" -> nil
        date_string -> "#{date_string}T00:00:00Z"
      end

    new_query = %{
      socket.assigns.search_query
      | build_tool: build_tool,
        depends: depends,
        updated_after: updated_after
    }

    {:noreply, push_query(socket, new_query)}
  end

  @impl true
  def handle_event("remove_filter", %{"key" => key}, socket) do
    field =
      case key do
        "build_tool" -> :build_tool
        "depends" -> :depends
        "updated_after" -> :updated_after
        _ -> nil
      end

    new_query =
      if field,
        do: Map.put(socket.assigns.search_query, field, nil),
        else: socket.assigns.search_query

    {:noreply, push_query(socket, new_query)}
  end

  @impl true
  def handle_event("sort_change", %{"sort" => sort}, socket) do
    url_params =
      %{sort: sort, search: socket.assigns.search}
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)

    {:noreply, push_patch(socket, to: ~p"/packages?#{url_params}")}
  end

  @impl true
  def handle_event("search_change", %{"search" => search}, socket) do
    search = nil_if_empty(search)

    url_params =
      %{sort: socket.assigns.sort, search: search}
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)

    {:noreply, push_patch(socket, to: ~p"/packages?#{url_params}")}
  end

  @impl true
  def handle_event("search_submit", %{"search" => search}, socket) do
    search = nil_if_empty(search)

    url_params =
      %{sort: socket.assigns.sort, search: search}
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)

    {:noreply, push_patch(socket, to: ~p"/packages?#{url_params}")}
  end

  @impl true
  def handle_event("clear_filters", _params, socket) do
    {:noreply, push_patch(socket, to: ~p"/packages?#{[sort: socket.assigns.sort]}")}
  end

  defp push_query(socket, %SearchQuery{} = query) do
    new_search = nil_if_empty(SearchQuery.serialize(query))

    url_params =
      %{sort: socket.assigns.sort, search: new_search}
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)

    push_patch(socket, to: ~p"/packages?#{url_params}")
  end

  defp nil_if_empty(nil), do: nil
  defp nil_if_empty(""), do: nil
  defp nil_if_empty(s), do: s

  defp sort(nil), do: sort("recent_downloads")
  defp sort("downloads"), do: sort("recent_downloads")
  defp sort(param), do: Hexpm.Utils.safe_to_atom(param, @sort_params)

  defp exact_match(_repositories, nil), do: nil

  defp exact_match(repositories, search) do
    search
    |> String.replace(" ", "_")
    |> String.split("/", parts: 2)
    |> case do
      [repository, package] ->
        if repository in Enum.map(repositories, & &1.name),
          do: Packages.get(repository, package)

      [term] ->
        try do
          Packages.get(repositories, term)
        rescue
          Ecto.MultipleResultsError -> nil
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
end
