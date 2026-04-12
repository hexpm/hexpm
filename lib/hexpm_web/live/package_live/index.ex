defmodule HexpmWeb.PackageLive.Index do
  use HexpmWeb, :live_view

  import HexpmWeb.PackageView, only: [downloads_for_package: 2]
  import HexpmWeb.PackageLive.FilterSidebar

  alias Hexpm.Repository.Package.SearchQuery

  @packages_per_page 30
  @sort_params ~w(name recent_downloads total_downloads inserted_at updated_at)
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
        depends_suggestions: []
      )

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, load_results(socket, params)}
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

    canonical_query = SearchQuery.serialize(search_query)

    assign(socket,
      search: search,
      search_query: search_query,
      canonical_query: canonical_query,
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
      <div class="max-w-7xl mx-auto px-4 py-8 lg:py-12">
        <%!-- Header --%>
        <div class="mb-8">
          <h1 class="text-grey-900 dark:text-grey-100 text-4xl font-bold mb-2">
            Packages
          </h1>
          <p class="text-grey-600 dark:text-grey-300 text-lg">
            Browse and discover packages for the Erlang ecosystem
          </p>
        </div>

        <button
          type="button"
          phx-click={
            Phoenix.LiveView.JS.toggle(to: "#filter-sidebar")
            |> Phoenix.LiveView.JS.toggle_attribute({"aria-expanded", "true", "false"})
          }
          aria-expanded="false"
          aria-controls="filter-sidebar"
          class="md:hidden mb-4 inline-flex items-center gap-2 px-4 py-2 text-sm font-medium text-grey-700 dark:text-grey-200 bg-grey-50 dark:bg-grey-800 border border-grey-200 dark:border-grey-600 rounded-lg hover:bg-grey-100 dark:hover:bg-grey-700 transition-colors"
        >
          <svg class="size-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M3 4a1 1 0 011-1h16a1 1 0 011 1v2.586a1 1 0 01-.293.707l-6.414 6.414a1 1 0 00-.293.707V17l-4 4v-6.586a1 1 0 00-.293-.707L3.293 7.293A1 1 0 013 6.586V4z"
            />
          </svg>
          Filters
        </button>
        <div class="flex flex-col md:flex-row gap-6">
          <.sidebar
            query={@search_query}
            depends_suggestions={@depends_suggestions}
          />
          <div class="flex-1 min-w-0">
            <%!-- Exact Match Section --%>
            <%= if @exact_match do %>
              <div class="mb-6 bg-green-50 dark:bg-green-900/20 border border-green-200 dark:border-green-800 rounded-xl p-6">
                <div class="flex items-center gap-2 mb-4">
                  <svg
                    class="size-5 text-green-600"
                    fill="none"
                    stroke="currentColor"
                    viewBox="0 0 24 24"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"
                    />
                  </svg>
                  <h3 class="text-green-900 dark:text-green-200 font-semibold text-lg">
                    Exact Match
                  </h3>
                </div>
                <ul class="bg-white dark:bg-grey-800 rounded-lg overflow-hidden divide-y divide-grey-200 dark:divide-grey-700">
                  {HexpmWeb.PackageView.render("_package.html",
                    exact_match?: true,
                    package: @exact_match,
                    package_downloads: downloads_for_package(@exact_match, @downloads),
                    view: @sort
                  )}
                </ul>
              </div>
            <% end %>

            <%!-- No Results --%>
            <%= if !@exact_match and @packages == [] do %>
              <div class="bg-grey-50 dark:bg-grey-800 rounded-xl p-12 text-center">
                <svg
                  class="mx-auto size-16 text-grey-300 mb-4"
                  fill="none"
                  stroke="currentColor"
                  viewBox="0 0 24 24"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z"
                  />
                </svg>
                <h3 class="text-grey-900 dark:text-grey-100 text-2xl font-semibold mb-2">
                  No Results Found
                </h3>
                <p class="text-grey-600 dark:text-grey-300">
                  Try adjusting your search
                </p>
              </div>
            <% end %>

            <%!-- Package List --%>
            <%= if @packages != [] do %>
              <%!-- Results Header with Sort Selector --%>
              <div class="flex flex-col sm:flex-row items-start sm:items-center justify-between gap-4 mb-6">
                <div>
                  <h2 class="text-grey-900 dark:text-grey-100 text-2xl font-semibold">
                    {if @exact_match, do: "Search Results", else: "All Packages"}
                  </h2>
                  <div class="flex items-center gap-3 mt-1">
                    <p class="text-grey-600 dark:text-grey-300 whitespace-nowrap">
                      {@package_count} {if @package_count == 1, do: "package", else: "packages"} found
                    </p>
                    <% total_pages = ceil(@package_count / @per_page) %>
                    <%= if total_pages > 1 do %>
                      <span class="text-grey-400 dark:text-grey-300">•</span>
                      <p class="text-grey-600 dark:text-grey-300 font-medium whitespace-nowrap">
                        Page {@page} of {total_pages}
                      </p>
                    <% end %>
                  </div>
                </div>

                <.sort_selector sort={@sort} />
              </div>

              <%!-- Package List --%>
              <div class="bg-white dark:bg-grey-800 border border-grey-200 dark:border-grey-700 rounded-xl overflow-hidden">
                <ul class="divide-y divide-grey-200 dark:divide-grey-700">
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
            <% end %>
          </div>
        </div>
      </div>
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

    suggestions =
      if depends,
        do: suggestions_for(depends, socket.assigns.repositories),
        else: []

    socket = assign(socket, depends_suggestions: suggestions)

    new_search = nil_if_empty(SearchQuery.serialize(new_query))

    url_params =
      %{sort: socket.assigns.sort, search: new_search}
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)

    {:noreply, push_patch(socket, to: ~p"/packages?#{url_params}")}
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

  defp suggestions_for(prefix, repositories) do
    repositories
    |> Hexpm.Repository.Package.search_by_prefix(prefix)
    |> Enum.map(& &1.name)
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
