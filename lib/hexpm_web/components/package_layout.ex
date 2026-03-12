defmodule HexpmWeb.Components.PackageLayout do
  @moduledoc """
  Shared layout component for the package detail pages (Readme, Activity, Versions).

  Renders the consistent header, tab navigation, and two-column layout.
  The sidebar (Checksum, Dependency Config, Package Details) is identical
  on every tab and is rendered directly by this component.
  Each page only supplies its own tab content via the inner_content slot.
  """
  use Phoenix.Component

  import HexpmWeb.Components.Badge
  import HexpmWeb.Components.Icons

  alias HexpmWeb.ViewHelpers

  attr :package, :map, required: true
  attr :current_release, :map, default: nil
  attr :dependants_count, :integer, default: 0
  attr :repository_name, :string, required: true
  attr :active_tab, :atom, required: true

  # Sidebar data — same on all tabs
  attr :docs_html_url, :string, default: nil
  attr :downloads, :map, default: %{}
  attr :daily_graph, :list, default: []

  # Dependants tab data — only loaded on the dependants page
  attr :dependants, :list, default: []
  attr :dependants_downloads, :map, default: %{}

  slot :inner_content, required: true

  def package_layout(assigns) do
    links = Enum.to_list(assigns.package.meta.links || [])

    github_link =
      Enum.find(links, fn {name, _url} ->
        String.downcase(to_string(name)) =~ "github"
      end)

    tools = [mix: "mix.exs", rebar: "rebar.config", erlang_mk: "erlang.mk"]

    {_labels, graph_points, _fill} =
      if assigns.daily_graph != [],
        do: ViewHelpers.time_series_graph(assigns.daily_graph),
        else: {[], "", ""}

    assigns =
      assigns
      |> assign(:github_link, github_link)
      |> assign(:description, assigns.package.meta.description)
      |> assign(:tools, tools)
      |> assign(:graph_points, graph_points)
      |> assign(:licenses, assigns.package.meta.licenses || [])
      |> assign(:build_tools, (assigns.current_release && assigns.current_release.meta.build_tools) || [])
      |> assign(:this_version_downloads, version_downloads(assigns))

    ~H"""
    <div class="tw:bg-grey-50 tw:min-h-screen">
      <%!-- Header Section --%>
      <div class="tw:max-w-7xl tw:mx-auto tw:pt-8 tw:pb-6">
        <div class="tw:flex tw:items-start tw:justify-between tw:gap-12">
          <%!-- Left: Package Name, Version, Description --%>
          <div class="tw:flex tw:flex-col tw:gap-2">
            <a
              href="/packages"
              class="tw:inline-flex tw:items-center tw:gap-1 tw:text-xs tw:font-medium tw:text-grey-400 tw:hover:text-purple-600 tw:transition-colors tw:w-fit"
            >
              {HexpmWeb.ViewIcons.icon(:heroicon, "arrow-left", class: "tw:size-3")}
              Packages
            </a>
            <div class="tw:flex tw:items-end tw:gap-4">
              <h1 class="tw:text-grey-900 tw:text-2xl tw:font-semibold">
                <a
                  href={ViewHelpers.path_for_package(@package)}
                  class="tw:hover:text-purple-600 tw:transition-colors"
                >
                  {ViewHelpers.package_name(@package)}
                </a>
              </h1>
              <%= if @current_release do %>
                <div class="tw:bg-grey-200 tw:flex tw:items-center tw:gap-1.5 tw:px-3 tw:py-1 tw:rounded-xl">
                  {HexpmWeb.ViewIcons.icon(:heroicon, "tag", class: "tw:size-3.5 tw:text-grey-500")}
                  <p class="tw:text-grey-700 tw:text-sm tw:font-medium">
                    v {@current_release.version}
                  </p>
                </div>
              <% end %>
            </div>
            <%= if @description do %>
              <p class="tw:text-grey-600 tw:max-w-[600px]">
                {ViewHelpers.text_length(@description, 300)}
              </p>
            <% end %>
          </div>

          <%!-- Right: Action Buttons — always visible --%>
          <div class="tw:flex tw:items-center tw:gap-3 tw:mt-6">
            <%= if @docs_html_url do %>
              <a
                href={@docs_html_url}
                class="tw:bg-grey-100 tw:flex tw:items-center tw:gap-2 tw:px-4 tw:py-2.5 tw:rounded-lg tw:text-grey-800 tw:text-sm tw:font-medium tw:hover:bg-grey-200 tw:transition-colors"
              >
                {HexpmWeb.ViewIcons.icon(:heroicon, "archive-box", class: "tw:size-4 tw:shrink-0")}
                <span>Online Documentation</span>
              </a>
            <% end %>
            <%= if @github_link do %>
              <% {_name, url} = @github_link %>
              <a
                href={url}
                rel="nofollow"
                class="tw:bg-grey-900 tw:flex tw:items-center tw:justify-center tw:p-2.5 tw:rounded-lg tw:hover:bg-grey-800 tw:transition-colors"
              >
                <.github_icon class="tw:size-4 tw:text-white" />
              </a>
            <% end %>
          </div>
        </div>
      </div>

      <%!-- Main Container with Sidebar --%>
      <div class="tw:max-w-7xl tw:mx-auto tw:pt-10">
        <div class="tw:flex tw:gap-5">
          <%!-- Left: Content Area --%>
          <div class="tw:flex-1 tw:min-w-0">
            <%!-- Tab Navigation --%>
            <div class="tw:flex tw:items-center tw:border-b tw:border-grey-200">
              <a
                href={ViewHelpers.path_for_package(@package)}
                class={tab_class(@active_tab == :readme)}
              >
                {HexpmWeb.ViewIcons.icon(:heroicon, "document-text", class: "tw:size-4.5")}
                <span>Readme</span>
              </a>
              <%= if @current_release do %>
                <a
                  href={dependencies_path(@package)}
                  class={tab_class(@active_tab == :dependencies)}
                >
                  {HexpmWeb.ViewIcons.icon(:heroicon, "document", class: "tw:size-4.5")}
                  <span>{Enum.count(@current_release.requirements || [])} Dependencies</span>
                </a>
              <% end %>
              <a
                href={dependents_path(@package)}
                class={tab_class(@active_tab == :dependants)}
              >
                {HexpmWeb.ViewIcons.icon(:heroicon, "document", class: "tw:size-4.5")}
                <span>{@dependants_count} Dependants</span>
              </a>
              <a
                href={audit_logs_path(@package)}
                class={tab_class(@active_tab == :activity)}
              >
                {HexpmWeb.ViewIcons.icon(:heroicon, "clock", class: "tw:size-4.5")}
                <span>Activity</span>
              </a>
              <a
                href={ViewHelpers.path_for_releases(@package)}
                class={tab_class(@active_tab == :versions)}
              >
                {HexpmWeb.ViewIcons.icon(:heroicon, "arrow-down-tray", class: "tw:size-4.5")}
                <span>Versions</span>
              </a>
            </div>

            <%!-- Tab Content --%>
            <div class="tw:py-6">
              {render_slot(@inner_content)}
            </div>
          </div>

          <%!-- Right: Sidebar — identical on every tab --%>
          <div class="tw:w-72 tw:shrink-0 tw:flex tw:flex-col tw:gap-6">
            <%!-- Checksum Card --%>
            <%= if @current_release do %>
              <div class="tw:bg-white tw:border tw:border-grey-200 tw:rounded-lg tw:p-5">
                <h3 class="tw:text-grey-700 tw:text-lg tw:font-semibold tw:mb-4">Checksum</h3>
                <div class="tw:flex tw:border tw:border-grey-200 tw:rounded tw:overflow-hidden">
                  <input
                    type="text"
                    class="tw:flex-1 tw:min-w-0 tw:px-3 tw:py-2.5 tw:text-grey-400 tw:text-xs tw:font-mono tw:bg-white tw:border-none tw:outline-none"
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
                    class="tw:bg-grey-50 tw:border-l tw:border-grey-200 tw:size-9 tw:flex tw:items-center tw:justify-center tw:hover:bg-grey-100 tw:transition-colors tw:shrink-0"
                  >
                    {HexpmWeb.ViewIcons.icon(:heroicon, "square-2-stack", class: "tw:size-4")}
                  </button>
                </div>
              </div>

              <%!-- Dependency Config Card --%>
              <div class="tw:bg-white tw:border tw:border-grey-200 tw:rounded-lg tw:p-5">
                <h3 class="tw:text-grey-700 tw:text-lg tw:font-semibold tw:mb-4">Dependency Config</h3>
                <%= for {tool, file} <- @tools do %>
                  <div class="tw:mb-4 tw:last:mb-0">
                    <p class="tw:text-grey-400 tw:text-xs tw:font-medium tw:mb-1.5">{file}</p>
                    <div class="tw:flex tw:border tw:border-grey-200 tw:rounded tw:overflow-hidden">
                      <input
                        type="text"
                        class="tw:flex-1 tw:min-w-0 tw:px-3 tw:py-2.5 tw:text-grey-400 tw:text-xs tw:font-mono tw:bg-white tw:border-none tw:outline-none"
                        value={HexpmWeb.PackageView.dep_snippet(tool, @package, @current_release)}
                        readonly
                        onfocus="this.select();"
                        id={"#{tool}-snippet"}
                        data-value={HexpmWeb.PackageView.dep_snippet(tool, @package, @current_release)}
                      />
                      <button
                        type="button"
                        phx-hook="CopyButton"
                        id={"#{tool}-copy-btn"}
                        data-copy-target={"#{tool}-snippet"}
                        class="tw:bg-grey-50 tw:border-l tw:border-grey-200 tw:size-9 tw:flex tw:items-center tw:justify-center tw:hover:bg-grey-100 tw:transition-colors tw:shrink-0"
                      >
                        {HexpmWeb.ViewIcons.icon(:heroicon, "square-2-stack", class: "tw:size-4")}
                      </button>
                    </div>
                  </div>
                <% end %>
              </div>

              <%!-- Package Details Card --%>
              <div class="tw:bg-white tw:border tw:border-grey-200 tw:rounded-lg tw:p-5">
                <h3 class="tw:text-grey-700 tw:text-lg tw:font-semibold tw:mb-4">Package Details</h3>

                <%!-- Downloads Chart --%>
                <%= if @graph_points != "" do %>
                  <div class="tw:mb-5">
                    <svg viewBox="0 0 260 70" class="tw:w-full tw:h-auto">
                      <defs>
                        <linearGradient id="pkg-grad" gradientUnits="userSpaceOnUse" x1="0" y1="0" x2="260" y2="70">
                          <stop offset="0%" style="stop-color:#4f28a7;" />
                          <stop offset="33%" style="stop-color:#7209b7;" />
                          <stop offset="66%" style="stop-color:#b5179e;" />
                          <stop offset="100%" style="stop-color:#f72585;" />
                        </linearGradient>
                      </defs>
                      <polyline
                        fill="none"
                        stroke="url(#pkg-grad)"
                        stroke-width="2"
                        stroke-linecap="round"
                        points={@graph_points}
                      />
                    </svg>
                  </div>
                <% end %>

                <%!-- Download Stats --%>
                <div class="tw:grid tw:grid-cols-3 tw:gap-3 tw:pb-4 tw:border-b tw:border-grey-200">
                  <div class="tw:flex tw:flex-col tw:gap-0.5">
                    <p class="tw:text-grey-400 tw:text-[10px] tw:font-medium tw:uppercase tw:tracking-wide">this version</p>
                    <p class="tw:text-grey-700 tw:text-base tw:font-bold">{ViewHelpers.human_number_space(@this_version_downloads)}</p>
                  </div>
                  <div class="tw:flex tw:flex-col tw:gap-0.5">
                    <p class="tw:text-grey-400 tw:text-[10px] tw:font-medium tw:uppercase tw:tracking-wide">last 7 days</p>
                    <p class="tw:text-grey-700 tw:text-base tw:font-bold">{ViewHelpers.human_number_space(@downloads["week"] || 0)}</p>
                  </div>
                  <div class="tw:flex tw:flex-col tw:gap-0.5">
                    <p class="tw:text-grey-400 tw:text-[10px] tw:font-medium tw:uppercase tw:tracking-wide">all time</p>
                    <p class="tw:text-grey-700 tw:text-base tw:font-bold">{ViewHelpers.human_number_space(@downloads["all"] || 0)}</p>
                  </div>
                </div>

                <%!-- Additional Details --%>
                <div class="tw:grid tw:grid-cols-2 tw:gap-x-3 tw:gap-y-4 tw:pt-4">
                  <div class="tw:flex tw:flex-col tw:gap-0.5">
                    <p class="tw:text-grey-400 tw:text-[10px] tw:font-medium tw:uppercase tw:tracking-wide">Last Updated</p>
                    <p class="tw:text-grey-700 tw:font-bold">{ViewHelpers.pretty_date(@current_release.inserted_at, :short)}</p>
                  </div>
                  <%= if @licenses != [] do %>
                    <div class="tw:flex tw:flex-col tw:gap-0.5">
                      <p class="tw:text-grey-400 tw:text-[10px] tw:font-medium tw:uppercase tw:tracking-wide">
                        {if length(@licenses) == 1, do: "License", else: "Licenses"}
                      </p>
                      <div class="tw:flex tw:items-center tw:gap-1.5 tw:flex-wrap">
                        <p class="tw:text-grey-700 tw:font-bold">{List.first(@licenses)}</p>
                        <%= if length(@licenses) > 1 do %>
                          <div class="tw:relative tw:group">
                            <span class="tw:text-xs tw:font-medium tw:text-purple-600 tw:cursor-default">
                              +{length(@licenses) - 1} more
                            </span>
                            <div class="tw:absolute tw:bottom-full tw:left-0 tw:mb-1.5 tw:hidden tw:group-hover:block tw:z-10">
                              <div class="tw:bg-grey-900 tw:text-white tw:text-xs tw:rounded-lg tw:px-3 tw:py-2 tw:whitespace-nowrap tw:shadow-lg">
                                <%= for license <- tl(@licenses) do %>
                                  <p>{license}</p>
                                <% end %>
                                <div class="tw:absolute tw:top-full tw:left-3 tw:border-4 tw:border-transparent tw:border-t-grey-900"></div>
                              </div>
                            </div>
                          </div>
                        <% end %>
                      </div>
                    </div>
                  <% end %>
                  <%= if @build_tools != [] do %>
                    <div class="tw:flex tw:flex-col tw:gap-0.5">
                      <p class="tw:text-grey-400 tw:text-[10px] tw:font-medium tw:uppercase tw:tracking-wide">Build Tools</p>
                      <div class="tw:flex tw:flex-wrap tw:gap-1.5">
                        <%= for tool <- Enum.uniq(@build_tools) do %>
                          <.badge variant="purple">{tool}</.badge>
                        <% end %>
                      </div>
                    </div>
                  <% end %>
                  <%= if @current_release.publisher do %>
                    <div class="tw:flex tw:flex-col tw:gap-0.5">
                      <p class="tw:text-grey-400 tw:text-[10px] tw:font-medium tw:uppercase tw:tracking-wide">Publisher</p>
                      <a
                        href={HexpmWeb.Router.user_path(@current_release.publisher)}
                        class="tw:flex tw:items-center tw:gap-1.5 tw:hover:text-purple-600 tw:transition-colors"
                      >
                        <img
                          src={ViewHelpers.gravatar_url(Hexpm.Accounts.User.email(@current_release.publisher, :gravatar), :small)}
                          class="tw:size-5 tw:rounded-full"
                          alt={@current_release.publisher.username}
                        />
                        <span class="tw:text-grey-700 tw:text-sm tw:font-medium">{@current_release.publisher.username}</span>
                      </a>
                    </div>
                  <% end %>
                </div>
              </div>
            <% end %>
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

  defp dependencies_path(%{repository: %{id: 1}} = package),
    do: "/packages/#{package.name}/dependencies"

  defp dependencies_path(package),
    do: "/packages/#{package.repository.name}/#{package.name}/dependencies"

  defp tab_class(true),
    do:
      "tw:flex tw:items-center tw:gap-1 tw:px-[18px] tw:py-3 tw:text-primary-default tw:font-medium tw:border-b-2 tw:border-primary-default tw:-mb-px"

  defp tab_class(false),
    do:
      "tw:flex tw:items-center tw:gap-1 tw:px-[18px] tw:py-3 tw:text-grey-500 tw:font-medium tw:hover:text-grey-700 tw:transition-colors"
end
