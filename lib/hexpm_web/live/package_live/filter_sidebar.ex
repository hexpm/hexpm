defmodule HexpmWeb.PackageLive.FilterSidebar do
  use Phoenix.Component

  alias Phoenix.LiveView.JS

  import HexpmWeb.ViewIcons, only: [icon: 3]

  alias Hexpm.Repository.Package.SearchQuery

  @build_tools ~w(mix rebar3 make gleam)

  attr :query, SearchQuery, required: true

  def sidebar(assigns) do
    assigns =
      assigns
      |> assign(:build_tools, @build_tools)
      |> assign(:active_count, active_count(assigns.query))

    ~H"""
    <aside
      class="hidden md:block w-full md:w-[264px] md:shrink-0 md:self-start md:sticky md:top-6"
      aria-label="Filters"
    >
      <div class="bg-white dark:bg-grey-800 border border-grey-100 dark:border-grey-700 rounded-xl p-5">
        <.filter_header active_count={@active_count} />
        <.filter_form
          id="filter-form"
          query={@query}
          build_tools={@build_tools}
          sync_to="filter-form-mobile"
        />
        <.filter_actions />
      </div>
    </aside>
    """
  end

  attr :query, SearchQuery, required: true

  def mobile_sheet(assigns) do
    assigns =
      assigns
      |> assign(:build_tools, @build_tools)
      |> assign(:active_count, active_count(assigns.query))

    ~H"""
    <div
      id="filter-sheet"
      class="md:hidden fixed inset-0 z-40 hidden flex-col"
      aria-hidden="true"
    >
      <button
        type="button"
        aria-label="Close filters"
        class="flex-1 bg-grey-900/45"
        phx-click={close_sheet()}
      ></button>
      <div class="bg-white dark:bg-grey-800 rounded-t-[20px] shadow-[0_-8px_24px_rgba(3,9,19,0.16)] pt-2 pb-6 flex flex-col max-h-[85%]">
        <div class="w-9 h-1 rounded-full bg-grey-200 dark:bg-grey-600 mx-auto mt-1.5 mb-1"></div>
        <div class="flex items-center justify-between px-4 pt-2.5 pb-3.5 border-b border-grey-100 dark:border-grey-700">
          <.filter_eyebrow active_count={@active_count} />
          <button
            type="button"
            aria-label="Close filters"
            class="w-8 h-8 rounded-lg inline-flex items-center justify-center text-grey-500 dark:text-grey-300 hover:bg-grey-50 dark:hover:bg-grey-700 transition-colors"
            phx-click={close_sheet()}
          >
            {icon(:heroicon, "x-mark", width: 18, height: 18)}
          </button>
        </div>

        <div class="overflow-y-auto px-4 pt-4 pb-1">
          <.filter_form
            id="filter-form-mobile"
            query={@query}
            build_tools={@build_tools}
            auto_recover="ignore"
            sync_to="filter-form"
          />
        </div>

        <div class="flex gap-2 px-4 pt-3.5 border-t border-grey-100 dark:border-grey-700 mt-2">
          <button
            type="button"
            phx-click="clear_filters"
            class="flex-1 h-11 rounded-lg border-[1.5px] border-grey-900 dark:border-grey-100 bg-transparent text-grey-900 dark:text-grey-100 text-sm font-medium hover:bg-grey-900 hover:text-white dark:hover:bg-grey-100 dark:hover:text-grey-900 transition-colors"
          >
            Clear all
          </button>
          <button
            type="button"
            class="flex-[2] h-11 rounded-lg border-0 bg-blue-600 text-white text-sm font-semibold hover:bg-blue-700 transition-colors"
            phx-click={close_sheet()}
          >
            Show results
          </button>
        </div>
      </div>
    </div>
    """
  end

  attr :active_count, :integer, required: true

  defp filter_header(assigns) do
    ~H"""
    <div class="flex items-center justify-between gap-2 pb-4 mb-4 border-b border-grey-100 dark:border-grey-700">
      <.filter_eyebrow active_count={@active_count} />
    </div>
    """
  end

  attr :active_count, :integer, required: true

  defp filter_eyebrow(assigns) do
    ~H"""
    <div class="flex items-baseline gap-2">
      <span class="text-tiny font-semibold uppercase tracking-[0.08em] text-grey-400 dark:text-grey-300">
        Filters
      </span>
      <span
        :if={@active_count > 0}
        class="text-tiny font-semibold text-primary-700 dark:text-primary-200 bg-primary-50 dark:bg-primary-900/30 border border-primary-100 dark:border-primary-800 px-2 py-0.5 rounded-full tabular-nums"
      >
        {@active_count} active
      </span>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :query, SearchQuery, required: true
  attr :build_tools, :list, required: true
  attr :auto_recover, :string, default: nil

  attr :sync_to, :string,
    default: nil,
    doc: "The ID of the parallel form that this form should sync its input values to client-side."

  defp filter_form(assigns) do
    ~H"""
    <form
      id={@id}
      phx-change="filter_change"
      phx-auto-recover={@auto_recover}
      phx-hook={@sync_to && "FormSync"}
      data-sync-to={@sync_to}
    >
      <div class="mb-[18px]">
        <label
          class="flex items-center justify-between gap-2 text-small font-semibold text-grey-600 dark:text-grey-200 mb-1.5"
          for={"#{@id}-build-tool"}
        >
          Build tool
        </label>
        <div class="relative">
          <select
            id={"#{@id}-build-tool"}
            name="build_tool"
            class="w-full h-9 pl-3 pr-8 text-small bg-white dark:bg-grey-700 border border-grey-200 dark:border-grey-600 rounded-lg text-grey-700 dark:text-grey-100 cursor-pointer appearance-none focus:outline-none focus:border-primary-600 focus:ring-[3px] focus:ring-primary-100 dark:focus:ring-primary-900/40 transition-[border-color,box-shadow] duration-150"
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
          <div class="absolute right-2.5 top-1/2 -translate-y-1/2 pointer-events-none text-grey-400 dark:text-grey-300">
            {icon(:heroicon, "chevron-down", width: 14, height: 14)}
          </div>
        </div>
      </div>

      <div class="mb-[18px]">
        <label
          class="flex items-center justify-between gap-2 text-small font-semibold text-grey-600 dark:text-grey-200 mb-1.5"
          for={"#{@id}-depends"}
        >
          Depends on
        </label>
        <div class="relative">
          <span class="absolute left-2.5 top-1/2 -translate-y-1/2 pointer-events-none text-grey-300 dark:text-grey-400">
            {icon(:heroicon, "magnifying-glass", width: 14, height: 14)}
          </span>
          <input
            id={"#{@id}-depends"}
            type="text"
            name="depends"
            value={@query.depends || ""}
            placeholder="package name"
            phx-debounce="300"
            class="w-full h-9 pl-[34px] pr-3 text-small bg-white dark:bg-grey-700 border border-grey-200 dark:border-grey-600 rounded-lg text-grey-700 dark:text-grey-100 placeholder:text-grey-300 dark:placeholder:text-grey-400 focus:outline-none focus:border-primary-600 focus:ring-[3px] focus:ring-primary-100 dark:focus:ring-primary-900/40 transition-[border-color,box-shadow] duration-150"
          />
        </div>
      </div>

      <div class="mb-5">
        <label
          class="flex items-center justify-between gap-2 text-small font-semibold text-grey-600 dark:text-grey-200 mb-1.5"
          for={"#{@id}-updated-after"}
        >
          <span>Updated after</span>
          <span class="text-tiny font-normal text-grey-400 dark:text-grey-300">last release</span>
        </label>
        <input
          id={"#{@id}-updated-after"}
          type="date"
          name="updated_after"
          value={date_value(@query.updated_after)}
          class="w-full h-9 px-3 text-small bg-white dark:bg-grey-700 border border-grey-200 dark:border-grey-600 rounded-lg text-grey-700 dark:text-grey-100 tabular-nums focus:outline-none focus:border-primary-600 focus:ring-[3px] focus:ring-primary-100 dark:focus:ring-primary-900/40 transition-[border-color,box-shadow] duration-150"
        />
      </div>
    </form>
    """
  end

  defp filter_actions(assigns) do
    ~H"""
    <div class="flex gap-2 pt-4 border-t border-grey-100 dark:border-grey-700">
      <button
        id="clear-filters"
        type="button"
        phx-click="clear_filters"
        class="flex-1 h-9 rounded-lg border-[1.5px] border-grey-900 dark:border-grey-100 bg-transparent text-grey-900 dark:text-grey-100 text-small font-medium hover:bg-grey-900 hover:text-white dark:hover:bg-grey-100 dark:hover:text-grey-900 transition-colors"
      >
        Clear all
      </button>
    </div>
    """
  end

  @doc """
  JS command to open the mobile filter sheet.
  """
  def open_sheet(js \\ %JS{}) do
    js
    |> JS.remove_class("hidden", to: "#filter-sheet")
    |> JS.add_class("flex", to: "#filter-sheet")
    |> JS.set_attribute({"aria-hidden", "false"}, to: "#filter-sheet")
  end

  @doc """
  JS command to close the mobile filter sheet.
  """
  def close_sheet(js \\ %JS{}) do
    js
    |> JS.add_class("hidden", to: "#filter-sheet")
    |> JS.remove_class("flex", to: "#filter-sheet")
    |> JS.set_attribute({"aria-hidden", "true"}, to: "#filter-sheet")
  end

  @doc """
  Returns the number of active filters on a SearchQuery.
  """
  def active_count(%SearchQuery{} = q) do
    [q.build_tool, q.depends, q.updated_after]
    |> Enum.count(&(not is_nil(&1)))
  end

  @doc """
  Returns the list of active filter chips as `{label, key, value}` tuples for
  rendering an "Active" chip strip. Each chip exposes the filter `key` so the
  parent LiveView can clear that filter individually.
  """
  def active_chips(%SearchQuery{} = q) do
    [
      {"build tool", "build_tool", q.build_tool},
      {"depends on", "depends", q.depends},
      {"updated after", "updated_after", format_date(q.updated_after)}
    ]
    |> Enum.reject(fn {_, _, v} -> is_nil(v) end)
  end

  defp format_date(nil), do: nil

  defp format_date(iso8601) do
    case DateTime.from_iso8601(iso8601) do
      {:ok, dt, _} -> Date.to_iso8601(DateTime.to_date(dt))
      _ -> iso8601
    end
  end

  defp date_value(nil), do: ""

  defp date_value(iso8601) do
    case DateTime.from_iso8601(iso8601) do
      {:ok, dt, _} -> Date.to_iso8601(DateTime.to_date(dt))
      _ -> ""
    end
  end
end
