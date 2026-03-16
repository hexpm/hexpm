defmodule HexpmWeb.Dashboard.Organization.Components.DangerZoneTab do
  use Phoenix.Component
  use PhoenixHTMLHelpers

  use Phoenix.VerifiedRoutes,
    endpoint: HexpmWeb.Endpoint,
    router: HexpmWeb.Router,
    statics: HexpmWeb.static_paths()

  import HexpmWeb.Components.Modal, only: [modal: 1, show_modal: 1, hide_modal: 1]
  import HexpmWeb.Components.Buttons, only: [button: 1]
  import HexpmWeb.Components.Input, only: [text_input: 1]

  attr :organization, :map, required: true

  def danger_zone_tab(assigns) do
    ~H"""
    <div class="space-y-4">
      <%!-- Section header --%>
      <div class="bg-white border border-red-200 rounded-lg overflow-hidden">
        <div class="px-6 py-5 border-b border-red-200 bg-red-50">
          <h2 class="text-red-700 text-lg font-semibold">Danger Zone</h2>
          <p class="text-sm text-red-600 mt-1">
            Actions here are irreversible. Please proceed with caution.
          </p>
        </div>

        <%!-- Leave organization --%>
        <div class="px-6 py-5 flex items-start justify-between gap-6">
          <div>
            <h3 class="text-sm font-semibold text-grey-900">Leave organization</h3>
            <p class="text-sm text-grey-500 mt-1">
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

      <.leave_modal organization={@organization} />
    </div>
    """
  end

  attr :organization, :map, required: true

  defp leave_modal(assigns) do
    ~H"""
    <.modal id="leave-org-modal" title="Leave organization">
      <p class="text-sm text-grey-600 mb-4">
        Are you sure you want to leave <strong>{@organization.name}</strong>?
        Once you leave the organization there is no going back.
      </p>
      <p class="text-sm text-grey-600 mb-6">
        Please type <strong>{@organization.name}</strong> to confirm.
      </p>
      <form
        id="leave-org-form"
        action={~p"/dashboard/orgs/#{@organization}/leave"}
        method="post"
      >
        <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
        <.text_input
          id="leave-org-name-input"
          name="organization_name"
          placeholder={@organization.name}
          required
          pattern={@organization.name}
          title={"Please type '#{@organization.name}' to confirm"}
        />
      </form>
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
