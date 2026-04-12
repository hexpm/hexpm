defmodule HexpmWeb.PackageLive.FilterSidebar do
  use Phoenix.Component

  import HexpmWeb.ViewIcons, only: [icon: 3]

  alias Hexpm.Repository.Package.SearchQuery

  @build_tools ~w(mix rebar3 make gleam)

  attr :query, SearchQuery, required: true
  attr :depends_suggestions, :list, default: []

  def sidebar(assigns) do
    assigns = assign(assigns, :build_tools, @build_tools)

    ~H"""
    <aside id="filter-sidebar" class="w-full md:w-60 shrink-0 hidden md:block" aria-label="Filters">
      <div class="bg-grey-50 dark:bg-grey-800 rounded-xl p-5 space-y-5">
        <form phx-change="filter_change" id="filter-form" class="space-y-5">
          <h3 class="text-grey-700 dark:text-grey-200 text-sm font-semibold uppercase tracking-wide">
            Filters
          </h3>

          <fieldset>
            <legend class="text-grey-700 dark:text-grey-200 text-sm font-semibold mb-3">
              Build tool
            </legend>
            <div class="relative">
              <select
                name="build_tool"
                class="w-full h-9 pl-3 pr-8 text-sm bg-white dark:bg-grey-700 border border-grey-200 dark:border-grey-600 rounded-lg text-grey-900 dark:text-grey-100 focus:outline-none focus:ring-1 focus:border-primary-600 focus:ring-primary-600 dark:focus:border-primary-400 dark:focus:ring-primary-400 cursor-pointer appearance-none"
              >
                <option value="" selected={is_nil(@query.build_tool)}>Any</option>
                <option
                  :for={tool <- @build_tools}
                  value={tool}
                  selected={@query.build_tool == tool}
                >
                  {tool}
                </option>
              </select>
              <div class="absolute right-3 top-1/2 -translate-y-1/2 pointer-events-none text-grey-400 dark:text-grey-300">
                {icon(:heroicon, "chevron-down", width: 15, height: 15)}
              </div>
            </div>
          </fieldset>

          <fieldset>
            <legend class="text-grey-700 dark:text-grey-200 text-sm font-semibold mb-3">
              Depends on
            </legend>
            <input
              type="text"
              name="depends"
              value={@query.depends || ""}
              list="depends-suggestions"
              placeholder="package name"
              phx-debounce="300"
              class="w-full h-9 px-3 text-sm bg-white dark:bg-grey-700 border border-grey-200 dark:border-grey-600 rounded-lg text-grey-900 dark:text-grey-100 placeholder:text-grey-400 dark:placeholder:text-grey-400 focus:outline-none focus:ring-1 focus:border-primary-600 focus:ring-primary-600 dark:focus:border-primary-400 dark:focus:ring-primary-400"
            />
            <datalist id="depends-suggestions">
              <option :for={name <- @depends_suggestions} value={name} />
            </datalist>
          </fieldset>

          <fieldset>
            <legend class="text-grey-700 dark:text-grey-200 text-sm font-semibold mb-3">
              Updated after
            </legend>
            <input
              type="date"
              name="updated_after"
              value={date_value(@query.updated_after)}
              class="w-full h-9 px-3 text-sm bg-white dark:bg-grey-700 border border-grey-200 dark:border-grey-600 rounded-lg text-grey-900 dark:text-grey-100 focus:outline-none focus:ring-1 focus:border-primary-600 focus:ring-primary-600 dark:focus:border-primary-400 dark:focus:ring-primary-400"
            />
          </fieldset>
        </form>

        <div class="pt-4 border-t border-grey-200 dark:border-grey-600">
          <button
            type="button"
            phx-click="clear_filters"
            class="w-full inline-flex items-center justify-center h-9 px-3 text-sm font-medium text-grey-700 dark:text-grey-200 bg-white dark:bg-grey-700 border border-grey-200 dark:border-grey-600 rounded-lg hover:bg-grey-100 dark:hover:bg-grey-600 transition-colors"
          >
            Clear all
          </button>
        </div>
      </div>
    </aside>
    """
  end

  defp date_value(nil), do: ""

  defp date_value(iso8601) do
    case DateTime.from_iso8601(iso8601) do
      {:ok, dt, _} -> Date.to_iso8601(DateTime.to_date(dt))
      _ -> ""
    end
  end
end
