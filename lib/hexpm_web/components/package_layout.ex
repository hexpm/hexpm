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
    <div class="bg-grey-50 min-h-screen">
      <%!-- Header Section --%>
      <div class="max-w-7xl mx-auto pt-8 pb-6">
        <div class="flex items-start justify-between gap-12">
          <%!-- Left: Package Name, Version, Description --%>
          <div class="flex flex-col gap-2">
            <a
              href="/packages"
              class="inline-flex items-center gap-1 text-xs font-medium text-grey-400 hover:text-purple-600 transition-colors w-fit"
            >
              {HexpmWeb.ViewIcons.icon(:heroicon, "arrow-left", class: "size-3")}
              Packages
            </a>
            <div class="flex items-end gap-4">
              <h1 class="text-grey-900 text-2xl font-semibold">
                <a
                  href={ViewHelpers.path_for_package(@package)}
                  class="text-grey-900 hover:text-purple-600 transition-colors"
                >
                  {ViewHelpers.package_name(@package)}
                </a>
              </h1>
              <%= if @current_release do %>
                <div class="bg-grey-200 flex items-center gap-1.5 px-3 py-1 rounded-xl">
                  {HexpmWeb.ViewIcons.icon(:heroicon, "tag", class: "size-3.5 text-grey-500")}
                  <p class="text-grey-700 text-sm font-medium">
                    v {@current_release.version}
                  </p>
                </div>
              <% end %>
            </div>
            <%= if @description do %>
              <p class="text-grey-600 max-w-[600px]">
                {ViewHelpers.text_length(@description, 300)}
              </p>
            <% end %>
          </div>

          <%!-- Right: Action Buttons — always visible --%>
          <div class="flex items-center gap-3 mt-6">
            <%= if @docs_html_url do %>
              <a
                href={@docs_html_url}
                class="bg-grey-100 flex items-center gap-2 px-4 py-2.5 rounded-lg text-grey-800 text-sm font-medium hover:bg-grey-200 transition-colors"
              >
                {HexpmWeb.ViewIcons.icon(:heroicon, "archive-box", class: "size-4 shrink-0")}
                <span>Online Documentation</span>
              </a>
            <% end %>
            <%= if @github_link do %>
              <% {_name, url} = @github_link %>
              <a
                href={url}
                rel="nofollow"
                class="bg-grey-900 flex items-center justify-center p-2.5 rounded-lg hover:bg-grey-800 transition-colors"
              >
                <.github_icon class="size-4 text-white" />
              </a>
            <% end %>
          </div>
        </div>
      </div>

      <%!-- Main Container with Sidebar --%>
      <div class="max-w-7xl mx-auto pt-10">
        <div class="flex gap-5">
          <%!-- Left: Content Area --%>
          <div class="flex-1 min-w-0">
            <%!-- Tab Navigation --%>
            <div class="flex items-center border-b border-grey-200">
              <a
                href={ViewHelpers.path_for_package(@package)}
                class={tab_class(@active_tab == :readme)}
              >
                {HexpmWeb.ViewIcons.icon(:heroicon, "document-text", class: "size-4.5")}
                <span>Readme</span>
              </a>
              <%= if @current_release do %>
                <a
                  href={dependencies_path(@package)}
                  class={tab_class(@active_tab == :dependencies)}
                >
                  {HexpmWeb.ViewIcons.icon(:heroicon, "document", class: "size-4.5")}
                  <span>{Enum.count(@current_release.requirements || [])} Dependencies</span>
                </a>
              <% end %>
              <a
                href={dependents_path(@package)}
                class={tab_class(@active_tab == :dependants)}
              >
                {HexpmWeb.ViewIcons.icon(:heroicon, "document", class: "size-4.5")}
                <span>{@dependants_count} Dependants</span>
              </a>
              <a
                href={audit_logs_path(@package)}
                class={tab_class(@active_tab == :activity)}
              >
                {HexpmWeb.ViewIcons.icon(:heroicon, "clock", class: "size-4.5")}
                <span>Activity</span>
              </a>
              <a
                href={ViewHelpers.path_for_releases(@package)}
                class={tab_class(@active_tab == :versions)}
              >
                {HexpmWeb.ViewIcons.icon(:heroicon, "arrow-down-tray", class: "size-4.5")}
                <span>Versions</span>
              </a>
            </div>

            <%!-- Tab Content --%>
            <div class="py-6">
              {render_slot(@inner_content)}
            </div>
          </div>

          <%!-- Right: Sidebar — identical on every tab --%>
          <div class="w-72 shrink-0 flex flex-col gap-6">
            <%!-- Checksum Card --%>
            <%= if @current_release do %>
              <div class="bg-white border border-grey-200 rounded-lg p-5">
                <h3 class="text-grey-700 text-lg font-semibold mb-4">Checksum</h3>
                <div class="flex border border-grey-200 rounded overflow-hidden">
                  <input
                    type="text"
                    class="flex-1 min-w-0 px-3 py-2.5 text-grey-400 text-xs font-mono bg-white border-none outline-none"
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
                    class="bg-grey-50 border-l border-grey-200 size-9 flex items-center justify-center hover:bg-grey-100 transition-colors shrink-0"
                  >
                    {HexpmWeb.ViewIcons.icon(:heroicon, "square-2-stack", class: "size-4")}
                  </button>
                </div>
              </div>

              <%!-- Dependency Config Card --%>
              <div class="bg-white border border-grey-200 rounded-lg p-5">
                <h3 class="text-grey-700 text-lg font-semibold mb-4">Dependency Config</h3>
                <%= for {tool, file} <- @tools do %>
                  <div class="mb-4 last:mb-0">
                    <p class="text-grey-400 text-xs font-medium mb-1.5">{file}</p>
                    <div class="flex border border-grey-200 rounded overflow-hidden">
                      <input
                        type="text"
                        class="flex-1 min-w-0 px-3 py-2.5 text-grey-400 text-xs font-mono bg-white border-none outline-none"
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
                        class="bg-grey-50 border-l border-grey-200 size-9 flex items-center justify-center hover:bg-grey-100 transition-colors shrink-0"
                      >
                        {HexpmWeb.ViewIcons.icon(:heroicon, "square-2-stack", class: "size-4")}
                      </button>
                    </div>
                  </div>
                <% end %>
              </div>

              <%!-- Package Details Card --%>
              <div class="bg-white border border-grey-200 rounded-lg p-5">
                <h3 class="text-grey-700 text-lg font-semibold mb-4">Package Details</h3>

                <%!-- Downloads Chart --%>
                <%= if @graph_points != "" do %>
                  <div class="mb-5">
                    <svg viewBox="0 0 260 70" class="w-full h-auto">
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
                <div class="grid grid-cols-3 gap-3 pb-4 border-b border-grey-200">
                  <div class="flex flex-col gap-0.5">
                    <p class="text-grey-400 text-[10px] font-medium uppercase tracking-wide">this version</p>
                    <p class="text-grey-700 text-base font-bold">{ViewHelpers.human_number_space(@this_version_downloads)}</p>
                  </div>
                  <div class="flex flex-col gap-0.5">
                    <p class="text-grey-400 text-[10px] font-medium uppercase tracking-wide">last 7 days</p>
                    <p class="text-grey-700 text-base font-bold">{ViewHelpers.human_number_space(@downloads["week"] || 0)}</p>
                  </div>
                  <div class="flex flex-col gap-0.5">
                    <p class="text-grey-400 text-[10px] font-medium uppercase tracking-wide">all time</p>
                    <p class="text-grey-700 text-base font-bold">{ViewHelpers.human_number_space(@downloads["all"] || 0)}</p>
                  </div>
                </div>

                <%!-- Additional Details --%>
                <div class="grid grid-cols-2 gap-x-3 gap-y-4 pt-4">
                  <div class="flex flex-col gap-0.5">
                    <p class="text-grey-400 text-[10px] font-medium uppercase tracking-wide">Last Updated</p>
                    <p class="text-grey-700 font-bold">{ViewHelpers.pretty_date(@current_release.inserted_at, :short)}</p>
                  </div>
                  <%= if @licenses != [] do %>
                    <div class="flex flex-col gap-0.5">
                      <p class="text-grey-400 text-[10px] font-medium uppercase tracking-wide">
                        {if length(@licenses) == 1, do: "License", else: "Licenses"}
                      </p>
                      <div class="flex items-center gap-1.5 flex-wrap">
                        <p class="text-grey-700 font-bold">{List.first(@licenses)}</p>
                        <%= if length(@licenses) > 1 do %>
                          <div class="relative group">
                            <span class="text-xs font-medium text-purple-600 cursor-default">
                              +{length(@licenses) - 1} more
                            </span>
                            <div class="absolute bottom-full left-0 mb-1.5 hidden group-hover:block z-10">
                              <div class="bg-grey-900 text-white text-xs rounded-lg px-3 py-2 whitespace-nowrap shadow-lg">
                                <%= for license <- tl(@licenses) do %>
                                  <p>{license}</p>
                                <% end %>
                                <div class="absolute top-full left-3 border-4 border-transparent border-t-grey-900"></div>
                              </div>
                            </div>
                          </div>
                        <% end %>
                      </div>
                    </div>
                  <% end %>
                  <%= if @build_tools != [] do %>
                    <div class="flex flex-col gap-0.5">
                      <p class="text-grey-400 text-[10px] font-medium uppercase tracking-wide">Build Tools</p>
                      <div class="flex flex-wrap gap-1.5">
                        <%= for tool <- Enum.uniq(@build_tools) do %>
                          <.badge variant="purple">{tool}</.badge>
                        <% end %>
                      </div>
                    </div>
                  <% end %>
                  <%= if @current_release.publisher do %>
                    <div class="flex flex-col gap-0.5">
                      <p class="text-grey-400 text-[10px] font-medium uppercase tracking-wide">Publisher</p>
                      <a
                        href={HexpmWeb.Router.user_path(@current_release.publisher)}
                        class="flex items-center gap-1.5 hover:text-purple-600 transition-colors"
                      >
                        <img
                          src={ViewHelpers.gravatar_url(Hexpm.Accounts.User.email(@current_release.publisher, :gravatar), :small)}
                          class="size-5 rounded-full"
                          alt={@current_release.publisher.username}
                        />
                        <span class="text-grey-700 text-sm font-medium">{@current_release.publisher.username}</span>
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
      "flex items-center gap-1 px-[18px] py-3 text-primary-default font-medium border-b-2 border-primary-default -mb-px"

  defp tab_class(false),
    do:
      "flex items-center gap-1 px-[18px] py-3 text-grey-500 font-medium hover:text-grey-700 transition-colors"
end
