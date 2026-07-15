defmodule HexpmWeb.Components.PackageLayout do
  @moduledoc """
  Shared layout component for the package detail pages (Readme, Activity, Versions).

  Renders the consistent header, tab navigation, and two-column layout.
  The sidebar (Checksum, Dependency Config, Package Details) is identical
  on every tab and is rendered directly by this component.
  Each page only supplies its own tab content via the inner_content slot.
  """
  use Phoenix.Component

  import HexpmWeb.Components.Chart

  use Phoenix.VerifiedRoutes,
    endpoint: HexpmWeb.Endpoint,
    router: HexpmWeb.Router,
    statics: HexpmWeb.static_paths()

  import HexpmWeb.Components.Badge

  alias Hexpm.Repository.Owners
  alias Hexpm.Security.Advisories
  alias HexpmWeb.ViewHelpers

  @package_reports_enabled Application.compile_env!(:hexpm, [:features, :package_reports])

  # All assigns below (except per-page ones) come from
  # `HexpmWeb.PackageLayoutAssigns.for_package/3`. Use that helper in every
  # controller action that renders this layout — missing assigns will fail
  # at compile/render time rather than silently producing broken UI.
  attr :package, :map, required: true
  attr :repository_name, :string, required: true
  attr :all_releases, :list, required: true
  attr :current_release, :map, required: true
  attr :versions_count, :integer, required: true
  attr :owners, :list, required: true
  attr :downloads, :map, required: true
  attr :daily_graph, :list, required: true
  attr :docs_html_url, :string, required: true
  attr :dependants_count, :integer, required: true
  attr :current_user, :map, required: true
  attr :graph_release, :map, default: nil

  # Per-page assigns
  attr :active_tab, :atom, required: true
  attr :version_pinned?, :boolean, default: false
  attr :wide?, :boolean, default: false
  attr :source_filename, :string, default: nil

  # Dependants tab data — only loaded on the dependants page
  attr :dependants, :list, default: []
  attr :dependants_downloads, :map, default: %{}

  slot :inner_content, required: true

  def package_layout(assigns) do
    tools = [mix: "mix.exs", rebar: "rebar.config", gleam: "Gleam", erlang_mk: "erlang.mk"]

    {graph_labels, graph_points, graph_fill} =
      if assigns.daily_graph != [],
        do: ViewHelpers.time_series_graph(assigns.daily_graph),
        else: {[], "", ""}

    y_axis_labels = Enum.zip(graph_labels, [194, 154, 114, 74, 34])

    links = Enum.to_list(assigns.package.meta.links || [])

    assigns =
      assigns
      |> assign(:links, links)
      |> assign(:description, assigns.package.meta.description)
      |> assign(:tools, tools)
      |> assign(:graph_points, graph_points)
      |> assign(:graph_fill, graph_fill)
      |> assign(:y_axis_labels, y_axis_labels)
      |> assign(:licenses, assigns.package.meta.licenses || [])
      |> assign(
        :build_tools,
        (assigns.current_release && assigns.current_release.meta.build_tools) || []
      )
      |> assign(:this_version_downloads, version_downloads(assigns))
      |> assign(:package_reports_enabled, @package_reports_enabled)
      |> assign(
        :dependency_count,
        assigns.current_release && Enum.count(assigns.current_release.requirements || [])
      )

    tabs = package_tabs(assigns)

    assigns =
      assigns
      |> assign(:tabs, tabs)
      |> assign(:active_package_tab, Enum.find(tabs, & &1.active))

    flash_visible = assigns.current_release && assigns.current_release.vulnerable?
    assigns = assign(assigns, :flash_visible, flash_visible)

    ~H"""
    <div class="bg-grey-50 dark:bg-grey-950 min-h-screen">
      <%!-- Header Section --%>
      <div class={[
        "max-w-7xl mx-auto px-4 pt-8",
        @flash_visible && "pb-0 lg:pb-0",
        !@flash_visible && "pb-2 lg:pb-6"
      ]}>
        <div class="flex flex-col lg:flex-row lg:items-start lg:justify-between gap-6 lg:gap-12">
          <%!-- Left: Package Name, Version, Description --%>
          <div class="flex flex-col gap-2">
            <a
              href={~p"/packages"}
              class="inline-flex items-center gap-1 text-xs font-medium text-grey-400 dark:text-grey-300 hover:text-purple-600 dark:hover:text-primary-300 transition-colors w-fit"
            >
              {HexpmWeb.ViewIcons.icon(:heroicon, "arrow-left", class: "size-3")} Packages
            </a>
            <div class="flex min-w-0 flex-wrap items-end gap-4">
              <h1 class="min-w-0 break-words text-grey-900 dark:text-grey-100 text-2xl font-semibold">
                <a
                  href={ViewHelpers.path_for_package(@package)}
                  class="text-grey-900 dark:text-grey-100 hover:text-purple-600 dark:hover:text-primary-300 transition-colors"
                >
                  {ViewHelpers.package_name(@package)}
                </a>
              </h1>
              <%= if @current_release do %>
                <details class="package-version-picker group relative">
                  <summary class="select-none flex cursor-pointer list-none items-center gap-1.5 rounded-xl border border-grey-300 bg-grey-100 px-3 py-1 text-sm font-medium text-grey-700 transition-colors hover:border-grey-400 hover:bg-grey-200 dark:border-grey-600 dark:bg-grey-800 dark:text-grey-200 dark:hover:border-grey-500 dark:hover:bg-grey-700 [&::-webkit-details-marker]:hidden">
                    {HexpmWeb.ViewIcons.icon(:heroicon, "tag",
                      class: "size-3.5 text-grey-500 dark:text-grey-300"
                    )}
                    <span class="font-mono">{@current_release.version}</span>
                    {HexpmWeb.ViewIcons.icon(:heroicon, "chevron-down",
                      class:
                        "size-3.5 text-grey-500 dark:text-grey-300 transition-transform group-open:rotate-180"
                    )}
                  </summary>

                  <div class="absolute right-0 top-full z-20 mt-2 max-h-80 w-52 max-w-[calc(100vw-2rem)] overflow-y-auto overflow-x-hidden rounded-lg border border-grey-200 bg-white shadow-lg sm:left-0 sm:right-auto sm:w-64 dark:border-grey-700 dark:bg-grey-800">
                    <%= for release <- @all_releases do %>
                      <a
                        href={path_for_tab(@active_tab, @package, release, @source_filename)}
                        class={version_item_class(@current_release.version == release.version)}
                      >
                        <span class="font-mono text-sm">{release.version}</span>
                        <%= if release.retirement do %>
                          <span class="inline-flex items-center rounded border border-yellow-300 bg-yellow-100 px-1.5 py-0.5 text-[10px] font-semibold uppercase tracking-wide text-yellow-900 dark:border-yellow-700/60 dark:bg-yellow-900/30 dark:text-yellow-100">
                            retired
                          </span>
                        <% end %>
                      </a>
                    <% end %>
                  </div>
                </details>
              <% end %>
            </div>
            <%= if @description do %>
              <p class="text-grey-600 dark:text-grey-300 max-w-[600px]">
                {ViewHelpers.text_length(@description, 300)}
              </p>
            <% end %>
            <%= if @current_release && @current_release.retirement do %>
              <div class="bg-red-50 border border-red-200 rounded-lg px-4 py-3 mt-2 text-sm text-red-800">
                {HexpmWeb.PackageView.retirement_html(@current_release.retirement)}
              </div>
            <% end %>
            <%= if @current_release && @current_release.vulnerable? do %>
              <div class="bg-red-600 border border-red-700 rounded-lg px-4 py-3 mt-2 text-sm text-white">
                <strong>Security advisory:</strong>
                This version has known vulnerabilities.
                <a
                  href={advisories_path(@package)}
                  class="underline font-semibold hover:text-red-100"
                >
                  View advisories
                </a>
              </div>
            <% end %>
          </div>

          <%!-- Right: Action Buttons — always visible --%>
          <div class="grid w-full auto-cols-fr grid-flow-col gap-2 lg:mt-6 lg:flex lg:w-auto lg:items-center lg:gap-3">
            <%= if @docs_html_url do %>
              <a
                href={@docs_html_url}
                class="bg-grey-100 dark:bg-grey-800 flex min-w-0 items-center justify-center gap-1.5 rounded-lg px-2 py-2.5 text-xs font-medium text-grey-800 transition-colors hover:bg-grey-200 dark:text-grey-100 dark:hover:bg-grey-700 sm:gap-2 sm:px-3 sm:text-sm lg:px-4"
              >
                {HexpmWeb.ViewIcons.icon(:heroicon, "book-open", class: "size-4 shrink-0")}
                <span class="truncate">HexDocs</span>
              </a>
            <% end %>
            <%= if @package_reports_enabled do %>
              <a
                href={"/reports/new?package=#{@package.name}&repository=#{@package.repository.name}"}
                class="bg-grey-100 dark:bg-grey-800 flex min-w-0 items-center justify-center gap-1.5 rounded-lg px-2 py-2.5 text-xs font-medium text-grey-800 transition-colors hover:bg-grey-200 dark:text-grey-100 dark:hover:bg-grey-700 sm:gap-2 sm:px-3 sm:text-sm lg:px-4"
              >
                {HexpmWeb.ViewIcons.icon(:heroicon, "flag", class: "size-4 shrink-0")}
                <span class="truncate">Report</span>
              </a>
            <% end %>
          </div>
        </div>
      </div>

      <%!-- Main Container with Sidebar --%>
      <div class="max-w-7xl mx-auto px-4 pt-4 lg:pt-10 pb-10">
        <div class="flex flex-col gap-5">
          <%!-- Tab Navigation --%>
          <details class="group relative md:hidden">
            <summary class="package-tabs-mobile-trigger select-none flex cursor-pointer list-none items-center justify-between rounded-xl border border-grey-200 bg-white px-4 py-3 text-left shadow-sm transition-colors hover:border-grey-300 dark:border-grey-700 dark:bg-grey-800 dark:hover:border-grey-600 [&::-webkit-details-marker]:hidden">
              <div class="flex min-w-0 items-center gap-3">
                {HexpmWeb.ViewIcons.icon(:heroicon, @active_package_tab.icon,
                  class: "size-5 shrink-0 text-grey-500 dark:text-grey-300"
                )}
                <div class="min-w-0">
                  <p class="text-[10px] font-medium uppercase tracking-wide text-grey-400 dark:text-grey-300">
                    Current section
                  </p>
                  <p class="truncate text-sm font-semibold text-grey-900 dark:text-grey-100">
                    {@active_package_tab.label}
                  </p>
                </div>
              </div>
              <div class="flex items-center gap-2 pl-4 text-grey-500 dark:text-grey-300">
                <span class="text-xs font-medium">Jump to</span>
                {HexpmWeb.ViewIcons.icon(:heroicon, "chevron-down",
                  class: "size-4 shrink-0 transition-transform group-open:rotate-180"
                )}
              </div>
            </summary>

            <div class="package-tabs-mobile-menu absolute inset-x-0 top-full z-20 mt-2 overflow-hidden rounded-xl border border-grey-200 bg-white shadow-lg dark:border-grey-700 dark:bg-grey-800">
              <%= for tab <- @tabs do %>
                <a
                  href={tab.path}
                  class={mobile_tab_class(tab.active)}
                >
                  <div class="flex min-w-0 items-center gap-3">
                    {HexpmWeb.ViewIcons.icon(:heroicon, tab.icon,
                      class: "size-4.5 shrink-0 text-grey-500 dark:text-grey-300"
                    )}
                    <span class="truncate">{tab.label}</span>
                  </div>
                  <%= if tab.active do %>
                    {HexpmWeb.ViewIcons.icon(:heroicon, "check",
                      class: "size-4 shrink-0 text-primary-default dark:text-white"
                    )}
                  <% end %>
                </a>
              <% end %>
            </div>
          </details>

          <div class="hidden items-center border-b border-grey-200 dark:border-grey-700 overflow-x-auto overflow-y-hidden md:flex">
            <%= for tab <- @tabs do %>
              <a
                href={tab.path}
                class={tab_class(tab.active)}
              >
                {HexpmWeb.ViewIcons.icon(:heroicon, tab.icon, class: "size-4.5")}
                <span>{tab.label}</span>
              </a>
            <% end %>
          </div>

          <div class={unless(@wide?, do: "flex flex-col lg:flex-row gap-5")}>
            <%!-- Left: Content Area --%>
            <div class="flex-1 min-w-0">
              <%!-- Tab Content --%>
              <div class="pt-1">
                {render_slot(@inner_content)}
              </div>
            </div>

            <%!-- Right: Sidebar — identical on every tab --%>
            <div :if={!@wide?} class="w-full lg:w-[373px] shrink-0 flex flex-col gap-6">
              <%!-- Checksum Card --%>
              <%= if @current_release do %>
                <div class="bg-white dark:bg-grey-800 border border-grey-200 dark:border-grey-700 rounded-lg p-5">
                  <h3 class="text-grey-700 dark:text-grey-100 text-lg font-semibold mb-4">
                    Checksum
                  </h3>
                  <div class="flex border border-grey-200 dark:border-grey-700 rounded overflow-hidden">
                    <input
                      type="text"
                      class="flex-1 min-w-0 px-3 py-2.5 text-grey-400 dark:text-grey-300 text-xs font-mono bg-white dark:bg-grey-800 border-none outline-none"
                      value={Base.encode16(@current_release.outer_checksum, case: :lower)}
                      readonly
                      onfocus="this.select();"
                      id="checksum-snippet"
                      data-value={Base.encode16(@current_release.outer_checksum, case: :lower)}
                    />
                    <button
                      type="button"
                      phx-hook="CopyButton"
                      id="checksum-copy-btn"
                      data-copy-target="checksum-snippet"
                      class="bg-grey-50 dark:bg-grey-900 border-l border-grey-200 dark:border-grey-700 size-9 flex items-center justify-center hover:bg-grey-100 dark:hover:bg-grey-700 transition-colors shrink-0"
                    >
                      {HexpmWeb.ViewIcons.icon(:heroicon, "square-2-stack", class: "size-4")}
                    </button>
                  </div>
                </div>

                <%!-- Dependency Config Card --%>
                <div class="bg-white dark:bg-grey-800 border border-grey-200 dark:border-grey-700 rounded-lg p-5">
                  <h3 class="text-grey-700 dark:text-grey-100 text-lg font-semibold mb-4">
                    Dependency Config
                  </h3>
                  <%= for {tool, file} <- @tools do %>
                    <div class="mb-4 last:mb-0">
                      <p class="text-grey-400 dark:text-grey-300 text-xs font-medium mb-1.5">
                        {file}
                      </p>
                      <div class="flex border border-grey-200 dark:border-grey-700 rounded overflow-hidden">
                        <input
                          type="text"
                          class="flex-1 min-w-0 px-3 py-2.5 text-grey-400 dark:text-grey-300 text-xs font-mono bg-white dark:bg-grey-800 border-none outline-none"
                          value={HexpmWeb.PackageView.dep_snippet(tool, @package, @current_release)}
                          readonly
                          onfocus="this.select();"
                          id={"#{tool}-snippet"}
                          data-value={
                            HexpmWeb.PackageView.dep_snippet(tool, @package, @current_release)
                          }
                        />
                        <button
                          type="button"
                          phx-hook="CopyButton"
                          id={"#{tool}-copy-btn"}
                          data-copy-target={"#{tool}-snippet"}
                          class="bg-grey-50 dark:bg-grey-900 border-l border-grey-200 dark:border-grey-700 size-9 flex items-center justify-center hover:bg-grey-100 dark:hover:bg-grey-700 transition-colors shrink-0"
                        >
                          {HexpmWeb.ViewIcons.icon(:heroicon, "square-2-stack", class: "size-4")}
                        </button>
                      </div>
                    </div>
                  <% end %>
                </div>

                <%!-- Package Details Card --%>
                <div class="bg-white dark:bg-grey-800 border border-grey-200 dark:border-grey-700 rounded-lg p-5">
                  <h3 class="text-grey-700 dark:text-grey-100 text-lg font-semibold mb-4">
                    Package Details
                  </h3>

                  <%!-- Downloads Chart --%>
                  <%= if is_binary(@graph_points) and @graph_points != "" do %>
                    <div class="mb-5">
                      <div class="flex items-center justify-between mb-2">
                        <span class="text-[10px] text-grey-400 dark:text-grey-300 font-medium uppercase tracking-wide">
                          Downloads
                        </span>
                        <span class="text-[10px] text-grey-400 dark:text-grey-300">
                          Last 30 days,
                          <%= if @graph_release do %>
                            {@graph_release.version}
                          <% else %>
                            all versions
                          <% end %>
                        </span>
                      </div>
                      <.downloads_chart
                        id={"pkg-chart-#{@package.id}"}
                        graph_points={@graph_points}
                        graph_fill={@graph_fill}
                        y_axis_labels={@y_axis_labels}
                      />
                    </div>
                  <% end %>

                  <%!-- Download Stats --%>
                  <div class="grid grid-cols-2 gap-3 pb-4 border-b border-grey-200 dark:border-grey-700">
                    <div class="flex flex-col gap-0.5">
                      <p class="text-grey-400 dark:text-grey-300 text-[10px] font-medium uppercase tracking-wide">
                        this version
                      </p>
                      <p class="text-grey-700 dark:text-grey-100 text-base font-bold">
                        {ViewHelpers.human_number_space(@this_version_downloads)}
                      </p>
                    </div>
                    <div class="flex flex-col gap-0.5">
                      <p class="text-grey-400 dark:text-grey-300 text-[10px] font-medium uppercase tracking-wide">
                        yesterday
                      </p>
                      <p class="text-grey-700 dark:text-grey-100 text-base font-bold">
                        {ViewHelpers.human_number_space(@downloads["day"] || 0)}
                      </p>
                    </div>
                    <div class="flex flex-col gap-0.5">
                      <p class="text-grey-400 dark:text-grey-300 text-[10px] font-medium uppercase tracking-wide">
                        last 7 days
                      </p>
                      <p class="text-grey-700 dark:text-grey-100 text-base font-bold">
                        {ViewHelpers.human_number_space(@downloads["week"] || 0)}
                      </p>
                    </div>
                    <div class="flex flex-col gap-0.5">
                      <p class="text-grey-400 dark:text-grey-300 text-[10px] font-medium uppercase tracking-wide">
                        all time
                      </p>
                      <p class="text-grey-700 dark:text-grey-100 text-base font-bold">
                        {ViewHelpers.human_number_space(@downloads["all"] || 0)}
                      </p>
                    </div>
                  </div>

                  <%!-- Additional Details --%>
                  <div class="grid grid-cols-2 gap-x-3 gap-y-4 pt-4">
                    <div class="flex flex-col gap-0.5">
                      <p class="text-grey-400 dark:text-grey-300 text-[10px] font-medium uppercase tracking-wide">
                        Last Updated
                      </p>
                      <p class="text-grey-700 dark:text-grey-100 font-bold">
                        {ViewHelpers.pretty_date(@current_release.inserted_at, :short)}
                      </p>
                    </div>
                    <%= if @licenses != [] do %>
                      <div class="flex flex-col gap-0.5">
                        <p class="text-grey-400 dark:text-grey-300 text-[10px] font-medium uppercase tracking-wide">
                          {if length(@licenses) == 1, do: "License", else: "Licenses"}
                        </p>
                        <div class="flex items-center gap-1.5 flex-wrap">
                          <p class="text-grey-700 dark:text-grey-100 font-bold">
                            {Enum.map_join(@licenses, ", ", &display_license/1)}
                          </p>
                        </div>
                      </div>
                    <% end %>
                    <%= if @build_tools != [] do %>
                      <div class="flex flex-col gap-0.5">
                        <p class="text-grey-400 dark:text-grey-300 text-[10px] font-medium uppercase tracking-wide">
                          Build Tools
                        </p>
                        <div class="flex flex-wrap gap-1.5">
                          <%= for tool <- Enum.uniq(@build_tools) do %>
                            <.badge variant="purple">{tool}</.badge>
                          <% end %>
                        </div>
                      </div>
                    <% end %>
                    <%= if @current_release.publisher do %>
                      <div class="flex flex-col gap-0.5">
                        <p class="text-grey-400 dark:text-grey-300 text-[10px] font-medium uppercase tracking-wide">
                          Publisher
                        </p>
                        <a
                          href={HexpmWeb.Router.user_path(@current_release.publisher)}
                          class="flex items-center gap-1.5 hover:text-purple-600 dark:hover:text-primary-300 transition-colors"
                        >
                          <img
                            src={
                              ViewHelpers.gravatar_url(
                                Hexpm.Accounts.User.email(@current_release.publisher, :gravatar),
                                :small
                              )
                            }
                            class="size-5 rounded-full"
                            alt={@current_release.publisher.username}
                          />
                          <span class="text-grey-700 dark:text-grey-100 text-sm font-medium">
                            {@current_release.publisher.username}
                          </span>
                        </a>
                      </div>
                    <% end %>
                  </div>
                </div>

                <%!-- Links Card --%>
                <%= if @links != [] do %>
                  <div class="bg-white dark:bg-grey-800 border border-grey-200 dark:border-grey-700 rounded-lg p-5">
                    <h3 class="text-grey-700 dark:text-grey-100 text-lg font-semibold mb-4">Links</h3>
                    <ul class="space-y-2">
                      <%= for {name, url} <- @links do %>
                        <li>
                          <a
                            href={ViewHelpers.safe_url(url)}
                            rel="nofollow"
                            class="text-sm text-blue-600 dark:text-blue-300 hover:text-blue-700 dark:hover:text-blue-200 hover:underline"
                          >
                            {name}
                          </a>
                        </li>
                      <% end %>
                    </ul>
                  </div>
                <% end %>

                <%!-- Owners Card --%>
                <%= if @owners != [] do %>
                  <% is_full_owner = Owners.full_owner?(@owners, @current_user) %>
                  <div class="bg-white dark:bg-grey-800 border border-grey-200 dark:border-grey-700 rounded-lg p-5">
                    <div class="flex items-center justify-between mb-4">
                      <h3 class="text-grey-700 dark:text-grey-100 text-lg font-semibold">
                        Owners
                      </h3>
                      <%= if is_full_owner do %>
                        <a
                          href={ViewHelpers.path_for_owners(@package)}
                          class="text-xs text-primary-600 hover:text-primary-700 dark:text-primary-400 dark:hover:text-primary-300 transition-colors"
                        >
                          Manage
                        </a>
                      <% end %>
                    </div>
                    <ul class="space-y-3">
                      <%= for owner <- @owners do %>
                        <li>
                          <a
                            href={HexpmWeb.Router.user_path(owner.user)}
                            class="flex items-center gap-2 hover:text-purple-600 dark:hover:text-primary-300 transition-colors"
                          >
                            <img
                              src={
                                ViewHelpers.gravatar_url(
                                  Hexpm.Accounts.User.email(owner.user, :gravatar),
                                  :small
                                )
                              }
                              class="size-6 rounded-full"
                              alt={owner.user.username}
                            />
                            <span class="text-grey-700 dark:text-grey-100 text-sm font-medium">
                              {owner.user.username}
                            </span>
                          </a>
                        </li>
                      <% end %>
                    </ul>
                  </div>
                <% end %>
              <% end %>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp version_downloads(%{current_release: nil}), do: 0

  defp version_downloads(%{current_release: release}) do
    case release do
      %{downloads: %{downloads: n}} when is_integer(n) -> n
      _ -> 0
    end
  end

  defp audit_logs_path(%{repository: %{id: 1}} = package),
    do: "/packages/#{package.name}/audit-logs"

  defp audit_logs_path(package),
    do: "/packages/#{package.repository.name}/#{package.name}/audit-logs"

  defp dependents_path(%{repository: %{id: 1}} = package),
    do: "/packages/#{package.name}/dependents"

  defp dependents_path(package),
    do: "/packages/#{package.repository.name}/#{package.name}/dependents"

  defp advisories_path(%{repository: %{id: 1}} = package),
    do: "/packages/#{package.name}/advisories"

  defp advisories_path(package),
    do: "/packages/#{package.repository.name}/#{package.name}/advisories"

  defp package_tabs(assigns) do
    [
      %{
        active: assigns.active_tab == :readme,
        icon: "document-text",
        label: "Readme",
        path: readme_path(assigns)
      },
      %{
        active: assigns.active_tab == :versions,
        icon: "tag",
        label:
          "#{assigns.versions_count} #{pluralize(assigns.versions_count, "Version", "Versions")}",
        path: ViewHelpers.path_for_releases(assigns.package)
      }
    ] ++
      dependency_tab(assigns) ++
      [
        %{
          active: assigns.active_tab == :dependants,
          icon: "puzzle-piece",
          label:
            "#{assigns.dependants_count} #{pluralize(assigns.dependants_count, "Dependant", "Dependants")}",
          path: dependents_path(assigns.package)
        }
      ] ++
      files_tab(assigns) ++
      advisories_tab(assigns) ++
      [
        %{
          active: assigns.active_tab == :activity,
          icon: "clock",
          label: "Activity",
          path: audit_logs_path(assigns.package)
        }
      ] ++ owners_tab(assigns)
  end

  defp files_tab(%{current_release: nil}), do: []

  defp files_tab(assigns) do
    if ViewHelpers.main_repository?(assigns.package) do
      [
        %{
          active: assigns.active_tab == :files,
          icon: "code-bracket",
          label: "Files",
          path: files_path(assigns)
        }
      ]
    else
      []
    end
  end

  defp owners_tab(assigns) do
    is_full_owner = Owners.full_owner?(assigns.owners, assigns.current_user)

    if is_full_owner do
      [
        %{
          active: assigns.active_tab == :owners,
          icon: "user-group",
          label: "Owners",
          path: ViewHelpers.path_for_owners(assigns.package)
        }
      ]
    else
      []
    end
  end

  defp dependency_tab(%{current_release: nil}), do: []

  defp dependency_tab(assigns) do
    [
      %{
        active: assigns.active_tab == :dependencies,
        icon: "cube",
        label:
          "#{assigns.dependency_count} #{pluralize(assigns.dependency_count, "Dependency", "Dependencies")}",
        path: dependencies_tab_path(assigns)
      }
    ]
  end

  defp advisories_tab(assigns) do
    count =
      assigns.package
      |> display_advisories()
      |> length()

    if count == 0 and assigns.active_tab != :advisories do
      []
    else
      [
        %{
          active: assigns.active_tab == :advisories,
          icon: "shield-exclamation",
          label: "#{count} #{pluralize(count, "Advisory", "Advisories")}",
          path: advisories_path(assigns.package)
        }
      ]
    end
  end

  defp display_advisories(%{security_advisories: %Ecto.Association.NotLoaded{}}), do: []

  defp display_advisories(%{security_advisories: advisories}) when is_list(advisories),
    do: Advisories.group_for_display(advisories)

  defp display_advisories(_package), do: []

  defp readme_path(%{version_pinned?: true, package: package, current_release: release})
       when not is_nil(release),
       do: ViewHelpers.path_for_release(package, release)

  defp readme_path(%{package: package}), do: ViewHelpers.path_for_package(package)

  defp dependencies_tab_path(%{version_pinned?: true, package: package, current_release: release})
       when not is_nil(release),
       do: ViewHelpers.path_for_dependencies(package, release)

  defp dependencies_tab_path(%{package: package}),
    do: ViewHelpers.path_for_dependencies(package)

  defp files_path(%{current_release: nil, package: package}),
    do: ViewHelpers.path_for_package(package)

  defp files_path(%{package: package, current_release: release, source_filename: filename})
       when is_binary(filename),
       do: source_path(package, release, filename)

  defp files_path(%{package: package, current_release: release}),
    do: source_path(package, release)

  defp tab_class(true),
    do:
      "flex items-center gap-1 px-[15px] py-3 text-grey-900 dark:text-white font-medium border-b-2 border-primary-default dark:border-white -mb-px whitespace-nowrap"

  defp tab_class(false),
    do:
      "flex items-center gap-1 px-[15px] py-3 text-grey-500 dark:text-grey-300 font-medium hover:text-grey-700 dark:hover:text-grey-200 transition-colors whitespace-nowrap"

  defp mobile_tab_class(true),
    do:
      "select-none flex items-center justify-between gap-3 bg-grey-50 px-4 py-3 text-sm font-medium text-grey-900 transition-colors dark:bg-grey-700/60 dark:text-white"

  defp mobile_tab_class(false),
    do:
      "select-none flex items-center justify-between gap-3 px-4 py-3 text-sm font-medium text-grey-600 transition-colors hover:bg-grey-50 hover:text-grey-900 dark:text-grey-200 dark:hover:bg-grey-700/60 dark:hover:text-white"

  defp pluralize(1, singular, _plural), do: singular
  defp pluralize(_count, _singular, plural), do: plural

  defp path_for_tab(:dependencies, package, release, _filename),
    do: ViewHelpers.path_for_dependencies(package, release)

  defp path_for_tab(:files, package, release, filename) when is_binary(filename),
    do: source_version_path(package, release, filename)

  defp path_for_tab(:files, package, release, _filename),
    do: source_path(package, release)

  defp path_for_tab(_tab, package, release, _filename),
    do: ViewHelpers.path_for_release(package, release)

  defp source_path(package, release) do
    ~p"/packages/#{package.name}/#{to_string(release.version)}/files"
  end

  defp source_path(package, release, filename) do
    ~p"/packages/#{package.name}/#{to_string(release.version)}/files/#{Path.split(filename)}"
  end

  defp source_version_path(package, release, filename) do
    ~p"/packages/#{package.name}/#{to_string(release.version)}/files/#{Path.split(filename)}?fallback=default"
  end

  defp version_item_class(true),
    do:
      "flex items-center justify-between gap-3 px-3 py-2 bg-grey-100 dark:bg-grey-700/60 text-grey-900 dark:text-white"

  defp version_item_class(false),
    do:
      "flex items-center justify-between gap-3 px-3 py-2 text-grey-700 dark:text-grey-200 hover:bg-grey-50 dark:hover:bg-grey-700/40 transition-colors"

  defp display_license("LicenseRef-" <> license_name), do: "#{license_name} (custom)"
  defp display_license(license), do: license
end
