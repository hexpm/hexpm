defmodule HexpmWeb.Dashboard.Policy.Components.PolicyNew do
  @moduledoc """
  Create-policy form for the organization dashboard.
  """
  use Phoenix.Component
  use PhoenixHTMLHelpers

  use Phoenix.VerifiedRoutes,
    endpoint: HexpmWeb.Endpoint,
    router: HexpmWeb.Router,
    statics: HexpmWeb.static_paths()

  import HexpmWeb.Components.Buttons, only: [button: 1]
  import HexpmWeb.Components.Form, only: [sudo_form: 1]
  import HexpmWeb.Components.Input, only: [text_input: 1, textarea_input: 1]
  import HexpmWeb.ViewIcons, only: [icon: 3]

  attr :current_user, :map, required: true
  attr :organization, :map, required: true
  attr :changeset, :any, required: true
  attr :paid?, :boolean, default: false

  def policy_new(assigns) do
    ~H"""
    <div class="space-y-6">
      <a
        href={~p"/dashboard/orgs/#{@organization}/policies"}
        class="inline-flex items-center gap-1 text-sm text-grey-600 dark:text-grey-300 hover:text-primary-600 dark:hover:text-primary-300 transition-colors"
      >
        {icon(:heroicon, "chevron-left", class: "w-4 h-4", width: 16, height: 16)} All policies
      </a>

      <div class="bg-white dark:bg-grey-800 border border-grey-200 dark:border-grey-700 rounded-lg p-6">
        <div class="flex items-center gap-3 mb-6">
          <div class="w-10 h-10 rounded-lg bg-primary-50 dark:bg-primary-900/30 flex items-center justify-center flex-shrink-0">
            {icon(:heroicon, "shield-check",
              class: "w-5 h-5 text-primary-600 dark:text-primary-300",
              width: 20,
              height: 20
            )}
          </div>
          <div>
            <h2 class="text-grey-900 dark:text-white text-lg font-semibold">New policy</h2>
            <p class="text-sm text-grey-500 dark:text-grey-300">
              Start from an empty policy, then configure each repository.
            </p>
          </div>
        </div>

        <.sudo_form
          :let={f}
          current_user={@current_user}
          for={@changeset}
          as={:policy}
          action={~p"/dashboard/orgs/#{@organization}/policies"}
        >
          <div class="space-y-4">
            <input
              type="hidden"
              name="policy[visibility]"
              value={if @paid?, do: "private", else: "public"}
            />

            <div>
              <.text_input
                field={f[:name]}
                label="Name"
                placeholder="e.g. production-baseline"
                required
              />
              <p class="text-xs text-grey-500 dark:text-grey-300 mt-1">
                Lowercase, numbers, <code class="font-mono">-</code>, <code class="font-mono">_</code>, <code class="font-mono">.</code>. Used as
                <code class="font-mono">{@organization.name}/&lt;name&gt;</code>
                wherever projects opt in.
              </p>
            </div>

            <.textarea_input
              field={f[:description]}
              label="Description"
              placeholder="What is this policy for?"
              rows="2"
            />

            <div class="flex justify-end gap-2 pt-2">
              <a
                href={~p"/dashboard/orgs/#{@organization}/policies"}
                class="inline-flex items-center justify-center h-9 px-4 rounded-md text-sm font-medium text-grey-600 dark:text-grey-300 hover:text-grey-900 dark:hover:text-white hover:bg-grey-100 dark:hover:bg-grey-700 transition-colors"
              >
                Cancel
              </a>
              <.button type="submit" variant="primary">Create policy</.button>
            </div>
          </div>
        </.sudo_form>
      </div>
    </div>
    """
  end
end
