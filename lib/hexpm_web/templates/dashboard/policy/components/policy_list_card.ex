defmodule HexpmWeb.Dashboard.Policy.Components.PolicyListCard do
  @moduledoc """
  Renders the policies listing for an organization: a header, count
  badge, and grid of existing policies plus a "create new" tile.
  """
  use Phoenix.Component
  use PhoenixHTMLHelpers

  use Phoenix.VerifiedRoutes,
    endpoint: HexpmWeb.Endpoint,
    router: HexpmWeb.Router,
    statics: HexpmWeb.static_paths()

  alias Hexpm.Repository.Policy

  import HexpmWeb.Components.Badge, only: [status_dot: 1]
  import HexpmWeb.Components.Buttons, only: [button_link: 1]
  import HexpmWeb.ViewIcons, only: [icon: 3]
  import HexpmWeb.ViewHelpers, only: [human_relative_time_from_now_text: 1]

  attr :current_user, :map, required: true
  attr :organization, :map, required: true
  attr :policies, :list, required: true
  attr :policy_stats, :map, default: %{}

  def policy_list_card(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex flex-col sm:flex-row sm:items-start sm:justify-between gap-4">
        <div class="min-w-0 flex-1">
          <h2 class="text-grey-900 dark:text-white text-2xl font-bold">Policies</h2>
          <p class="text-grey-500 dark:text-grey-300 text-sm mt-2 max-w-3xl">
            Policies define dependency resolution rules that projects can opt into.
            Rules are evaluated separately for each repository.
          </p>
        </div>
        <div class="flex items-center gap-2 flex-shrink-0 w-full sm:w-auto">
          <.button_link
            href={~p"/docs/dependency-policies"}
            variant="outline"
            size="sm"
          >
            Documentation
          </.button_link>
        </div>
      </div>

      <div class="flex items-start gap-2 rounded-lg border border-blue-300 dark:border-blue-700 bg-blue-100/70 dark:bg-blue-900/30 p-3 text-sm text-blue-900 dark:text-blue-100">
        {icon(:heroicon, "information-circle",
          class: "w-4 h-4 flex-shrink-0 mt-0.5",
          width: 16,
          height: 16
        )}
        <span>
          Dependency policies are enforced by Hex v2.5, which has not been released yet. Policies you create now will take effect once you have updated to Hex v2.5 and configured it to use the policy.
        </span>
      </div>

      <div
        :if={@policies == []}
        class="rounded-lg border border-dashed border-grey-300 dark:border-grey-700 bg-white dark:bg-grey-800 min-h-[360px] flex items-center justify-center px-6 py-12"
      >
        <div class="max-w-md text-center">
          <div class="mx-auto w-16 h-16 flex items-center justify-center text-grey-400 dark:text-grey-500 mb-5">
            {icon(:heroicon, "shield-check", class: "w-14 h-14", width: 56, height: 56)}
          </div>
          <h3 class="text-grey-900 dark:text-white text-lg font-semibold">No policies yet</h3>
          <p class="text-sm text-grey-500 dark:text-grey-300 mt-2 mb-6">
            A policy controls which packages your projects can install. Create one and configure each repository.
          </p>
          <a
            href={~p"/dashboard/orgs/#{@organization}/policies/new"}
            class={[
              "group inline-flex items-center gap-4 rounded-lg px-5 py-4 text-left",
              "border border-dashed border-grey-300 dark:border-grey-700",
              "hover:border-primary-600 hover:bg-primary-50 dark:hover:bg-primary-900/20",
              "transition-colors"
            ]}
          >
            <span class="w-11 h-11 rounded-lg bg-grey-100 dark:bg-grey-700 group-hover:bg-primary-100 dark:group-hover:bg-primary-900/40 text-grey-600 dark:text-grey-300 group-hover:text-primary-700 dark:group-hover:text-primary-200 flex items-center justify-center transition-colors">
              {icon(:heroicon, "plus", class: "w-5 h-5", width: 20, height: 20)}
            </span>
            <span>
              <span class="block text-sm font-semibold text-grey-900 dark:text-white">
                Create policy
              </span>
              <span class="block text-xs text-grey-500 dark:text-grey-300 mt-1">
                Start from an empty policy and configure each repository.
              </span>
            </span>
          </a>
        </div>
      </div>

      <div :if={@policies != []} class="grid grid-cols-1 gap-4">
        <.policy_card
          :for={policy <- @policies}
          organization={@organization}
          policy={policy}
          stats={Map.get(@policy_stats, policy.id, %{})}
        />

        <a
          href={~p"/dashboard/orgs/#{@organization}/policies/new"}
          class={[
            "group block rounded-lg p-5",
            "border-2 border-dashed border-grey-200 dark:border-grey-700",
            "hover:border-primary-600 hover:bg-primary-50 dark:hover:bg-primary-900/20",
            "text-grey-500 dark:text-grey-400 hover:text-primary-700 dark:hover:text-primary-200",
            "flex flex-col items-center justify-center text-center min-h-[132px]",
            "transition-colors"
          ]}
        >
          <div class="w-10 h-10 rounded-lg bg-grey-100 dark:bg-grey-700 group-hover:bg-primary-100 dark:group-hover:bg-primary-900/40 group-hover:text-primary-700 dark:group-hover:text-primary-200 flex items-center justify-center mb-3 transition-colors">
            {icon(:heroicon, "plus", class: "w-5 h-5", width: 20, height: 20)}
          </div>
          <h3 class="text-grey-700 dark:text-grey-200 text-sm font-semibold mb-1">
            Create policy
          </h3>
          <p class="text-xs text-grey-500 dark:text-grey-400 max-w-[16rem]">
            Start from an empty policy and configure each repository.
          </p>
        </a>
      </div>
    </div>
    """
  end

  attr :organization, :map, required: true
  attr :policy, :map, required: true
  attr :stats, :map, required: true

  defp policy_card(assigns) do
    ~H"""
    <article class="bg-white dark:bg-grey-800 border border-grey-200 dark:border-grey-700 rounded-lg p-5">
      <div class="flex items-start gap-3 mb-3">
        <div class="w-10 h-10 rounded-lg bg-primary-50 dark:bg-primary-900/30 flex items-center justify-center flex-shrink-0">
          {icon(:heroicon, "shield-check",
            class: "w-5 h-5 text-primary-600 dark:text-primary-300",
            width: 20,
            height: 20
          )}
        </div>
        <div class="min-w-0 flex-1">
          <a
            href={~p"/dashboard/orgs/#{@organization}/policies/#{@policy.name}"}
            class="text-grey-900 dark:text-white text-base font-semibold hover:text-primary-600 dark:hover:text-primary-300 transition-colors"
          >
            {@policy.name}
          </a>
          <div class="font-mono text-xs text-grey-400 dark:text-grey-500 mt-0.5">
            {@organization.name}/{@policy.name}
          </div>
        </div>
        <.status_pill dot={visibility_dot(@policy.visibility)}>
          {String.capitalize(@policy.visibility)}
        </.status_pill>
        <a
          href={~p"/dashboard/orgs/#{@organization}/policies/#{@policy.name}"}
          class="flex-shrink-0 text-grey-300 dark:text-grey-500 hover:text-primary-600 transition-colors mt-1"
          aria-label="Open policy"
        >
          {icon(:heroicon, "chevron-right", class: "w-4 h-4", width: 16, height: 16)}
        </a>
      </div>

      <p class="text-sm text-grey-500 dark:text-grey-300 mb-4 line-clamp-2">
        {description_text(@policy.description)}
      </p>

      <div class="space-y-2 mb-4">
        <.repo_summary_line :for={repo <- @policy.repositories} repo={repo} />
      </div>

      <div class="border-t border-grey-100 dark:border-grey-700 pt-3 flex items-center justify-between gap-3 text-xs text-grey-500 dark:text-grey-300">
        <span>Updated {human_relative_time_from_now_text(@policy.updated_at)}</span>
        <div class="flex items-center gap-3">
          <.button_link
            href={~p"/dashboard/orgs/#{@organization}/policies/#{@policy.name}"}
            variant="outline"
            size="sm"
          >
            <span class="inline-flex items-center gap-1">
              {icon(:heroicon, "pencil", class: "w-3.5 h-3.5", width: 14, height: 14)} Edit
            </span>
          </.button_link>
          <span :if={@stats[:rev]} class="font-mono">rev {@stats[:rev]}</span>
        </div>
      </div>
    </article>
    """
  end

  attr :repo, :map, required: true

  defp repo_summary_line(assigns) do
    assigns =
      assigns
      |> assign(:chips, restriction_chips(assigns.repo))
      |> assign(:overrides, length(assigns.repo.overrides))

    ~H"""
    <div class="flex flex-wrap items-center gap-x-2 gap-y-1 text-xs rounded-lg bg-grey-50 dark:bg-grey-900 border border-grey-200 dark:border-grey-700 px-3 py-2">
      <span class="inline-flex items-center gap-1 font-medium text-grey-700 dark:text-grey-200">
        {icon(:heroicon, repo_icon(@repo.repository), class: "w-3.5 h-3.5", width: 13, height: 13)} {@repo.repository}
      </span>
      <span :if={@chips == [] and @overrides == 0} class="text-grey-400 dark:text-grey-500 italic">
        no restrictions
      </span>
      <.status_pill :for={{dot, label} <- @chips} dot={dot}>{label}</.status_pill>
      <span
        :if={@overrides > 0}
        class="inline-flex items-center px-2.5 py-1 rounded-full text-xs font-medium border bg-yellow-50 text-yellow-800 border-yellow-200 dark:bg-yellow-900/20 dark:text-yellow-300 dark:border-yellow-800"
      >
        {@overrides} {ngettext("override", "overrides", @overrides)}
      </span>
    </div>
    """
  end

  attr :dot, :string, default: "grey"
  slot :inner_block, required: true

  defp status_pill(assigns) do
    ~H"""
    <span class={[
      "inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-medium border",
      pill_variant(@dot)
    ]}>
      <.status_dot variant={@dot} />
      {render_slot(@inner_block)}
    </span>
    """
  end

  defp pill_variant("blue"),
    do:
      "bg-blue-50 text-blue-700 border-blue-200 dark:bg-blue-900/20 dark:text-blue-300 dark:border-blue-800"

  defp pill_variant("purple"),
    do:
      "bg-primary-50 text-primary-700 border-primary-200 dark:bg-primary-900/20 dark:text-primary-300 dark:border-primary-700"

  defp pill_variant("yellow"),
    do:
      "bg-yellow-50 text-yellow-700 border-yellow-200 dark:bg-yellow-900/20 dark:text-yellow-300 dark:border-yellow-800"

  defp pill_variant("red"),
    do:
      "bg-red-50 text-red-700 border-red-200 dark:bg-red-900/20 dark:text-red-300 dark:border-red-800"

  defp pill_variant("green"),
    do:
      "bg-green-50 text-green-700 border-green-200 dark:bg-green-900/20 dark:text-green-300 dark:border-green-800"

  defp pill_variant(_),
    do:
      "bg-grey-100 text-grey-600 border-grey-200 dark:bg-grey-900 dark:text-grey-300 dark:border-grey-700"

  defp visibility_dot("public"), do: "blue"
  defp visibility_dot("private"), do: "purple"
  defp visibility_dot(_), do: "grey"

  defp description_text(nil), do: "No description yet."
  defp description_text(""), do: "No description yet."
  defp description_text(value), do: value

  defp severity_label(value) when is_integer(value) do
    Enum.at(Policy.severity_names(), value, to_string(value))
  end

  defp severity_label(other), do: to_string(other)

  # The restriction limits set on a repository tab as {dot, label} chips.
  defp restriction_chips(repo) do
    []
    |> maybe_chip(repo.cooldown, fn cooldown -> {"blue", cooldown} end)
    |> maybe_chip(repo.advisory_min_severity, fn severity ->
      {"yellow", "≥ #{severity_label(severity)}"}
    end)
    |> maybe_chip(present_list(repo.retirement_reasons), fn reasons ->
      {"red", "#{length(reasons)} retirement"}
    end)
    |> Enum.reverse()
  end

  defp maybe_chip(chips, nil, _fun), do: chips
  defp maybe_chip(chips, value, fun), do: [fun.(value) | chips]

  defp present_list([]), do: nil
  defp present_list(nil), do: nil
  defp present_list(list) when is_list(list), do: list

  defp ngettext(singular, _plural, 1), do: singular
  defp ngettext(_singular, plural, _count), do: plural

  defp repo_icon("hexpm"), do: "globe-alt"
  defp repo_icon(_), do: "building-office"
end
