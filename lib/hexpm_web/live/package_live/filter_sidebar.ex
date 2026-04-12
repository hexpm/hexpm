defmodule HexpmWeb.PackageLive.FilterSidebar do
  use Phoenix.Component

  alias Hexpm.Repository.Package.SearchQuery

  @build_tools ~w(mix rebar3 make gleam)

  attr :query, SearchQuery, required: true

  def sidebar(assigns) do
    assigns = assign(assigns, :build_tools, @build_tools)

    ~H"""
    <aside id="filter-sidebar" class="w-56 shrink-0" aria-label="Filters">
      <form phx-change="filter_change" id="filter-form">
        <h3 class="font-semibold text-grey-900 dark:text-grey-100 mb-3">Filters</h3>

        <fieldset class="mb-6">
          <legend class="text-sm font-medium mb-2">Build tool</legend>
          <div class="space-y-1">
            <label :for={tool <- @build_tools} class="flex items-center gap-2 text-sm">
              <input
                type="checkbox"
                name={"build_tool[#{tool}]"}
                value="true"
                checked={tool in @query.build_tools}
              />
              <span>{tool}</span>
            </label>
          </div>
        </fieldset>
      </form>
    </aside>
    """
  end
end
