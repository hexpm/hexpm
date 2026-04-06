defmodule HexpmWeb.Dashboard.Organization.Components.DangerZoneTab do
  use Phoenix.Component
  use PhoenixHTMLHelpers

  use Phoenix.VerifiedRoutes,
    endpoint: HexpmWeb.Endpoint,
    router: HexpmWeb.Router,
    statics: HexpmWeb.static_paths()

  import HexpmWeb.Components.Buttons, only: [button: 1]
  import HexpmWeb.Components.Form, only: [sudo_form: 1]
  import HexpmWeb.Components.Input, only: [text_input: 1]
  import HexpmWeb.Components.Modal, only: [modal: 1, show_modal: 1, hide_modal: 1]

  attr :current_user, :map, required: true
  attr :organization, :map, required: true

  def danger_zone_tab(assigns) do
    ~H"""
    <div class="space-y-4">
      <%!-- Section header --%>
      <div class="bg-white dark:bg-grey-800 border border-red-200 dark:border-red-800 rounded-lg overflow-hidden">
        <div class="px-6 py-5 border-b border-red-200 dark:border-red-800 bg-red-50 dark:bg-red-700">
          <h2 class="text-red-700 dark:text-white text-lg font-semibold">Danger Zone</h2>
          <p class="text-sm dark:text-white text-red-600 mt-1">
            Actions here are irreversible. Please proceed with caution.
          </p>
        </div>

        <%!-- Leave organization --%>
        <div class="px-6 py-5 flex items-start justify-between gap-6">
          <div>
            <h3 class="text-sm font-semibold text-grey-900 dark:text-white">Leave organization</h3>
            <p class="text-sm text-grey-500 dark:text-grey-300 mt-1">
              Once you leave the organization there is no going back, please be certain.
            </p>
          </div>
          <.button
            type="button"
            variant="danger"
            size="sm"
            class="shrink-0"
            phx-click={show_modal("leave-org-modal")}
          >
            Leave organization
          </.button>
        </div>
      </div>

      <.leave_modal current_user={@current_user} organization={@organization} />
    </div>
    """
  end

  attr :current_user, :map, required: true
  attr :organization, :map, required: true

  defp leave_modal(assigns) do
    ~H"""
    <.modal id="leave-org-modal" title="Leave organization">
      <p class="text-sm text-grey-600 dark:text-grey-300 mb-4">
        Are you sure you want to leave <strong class="text-grey-900 dark:text-white">{@organization.name}</strong>?
        Once you leave the organization there is no going back.
      </p>
      <p class="text-sm text-grey-600 dark:text-grey-300 mb-6">
        Please type <strong class="text-grey-900 dark:text-white">{@organization.name}</strong>
        to confirm.
      </p>
      <.sudo_form
        current_user={@current_user}
        action={~p"/dashboard/orgs/#{@organization}/leave"}
        id="leave-org-form"
      >
        <.text_input
          id="leave-org-name-input"
          name="organization_name"
          placeholder={@organization.name}
          required
          pattern={@organization.name}
          title={"Please type '#{@organization.name}' to confirm"}
        />
      </.sudo_form>
      <:footer>
        <.button type="button" variant="secondary" phx-click={hide_modal("leave-org-modal")}>
          Cancel
        </.button>
        <.button type="submit" form="leave-org-form" variant="danger">
          Leave organization
        </.button>
      </:footer>
    </.modal>
    """
  end
end
