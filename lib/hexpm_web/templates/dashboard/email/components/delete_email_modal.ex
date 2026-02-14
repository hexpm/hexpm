defmodule HexpmWeb.Dashboard.Email.Components.DeleteEmailModal do
  @moduledoc """
  Modal for deleting an email address with conditional logic for primary emails.
  """
  use Phoenix.Component
  use PhoenixHTMLHelpers
  import HexpmWeb.Components.Buttons
  import HexpmWeb.Components.Modal, only: [show_modal: 2]

  use Phoenix.VerifiedRoutes,
    endpoint: HexpmWeb.Endpoint,
    router: HexpmWeb.Router,
    statics: HexpmWeb.static_paths()

  attr :email, :map, required: true
  attr :csrf_token, :string, required: true

  def delete_email_modal(assigns) do
    modal_id = "delete-email-#{assigns.email.id}"
    assigns = assign(assigns, :modal_id, modal_id)

    ~H"""
    <%= if @email.primary do %>
      <%!-- Cannot Delete Primary Email Modal --%>
      <HexpmWeb.Components.Modal.modal id={@modal_id} max_width="md">
        <:header>
          <h2 class="tw:text-lg tw:font-semibold tw:text-grey-900">
            Cannot Delete Primary Email
          </h2>
        </:header>

        <p class="tw:text-grey-700">
          You cannot delete your primary email address. Please add a new email and set it as primary before deleting this one.
        </p>

        <:footer>
          <.button
            type="button"
            variant="outline"
            phx-click={HexpmWeb.Components.Modal.hide_modal(@modal_id)}
          >
            Cancel
          </.button>
          <.button
            type="button"
            phx-click={
              HexpmWeb.Components.Modal.hide_modal(@modal_id)
              |> show_modal("add-email-modal")
            }
          >
            Add New Email
          </.button>
        </:footer>
      </HexpmWeb.Components.Modal.modal>
    <% else %>
      <%!-- Confirm Delete Email Modal --%>
      <HexpmWeb.Components.Modal.modal id={@modal_id} max_width="md">
        <:header>
          <h2 class="tw:text-lg tw:font-semibold tw:text-grey-900">
            Delete Email?
          </h2>
        </:header>

        <p class="tw:text-grey-700">
          Are you sure you want to delete <strong>{@email.email}</strong>? This action cannot be undone.
        </p>

        <:footer>
          <.button
            type="button"
            variant="outline"
            phx-click={HexpmWeb.Components.Modal.hide_modal(@modal_id)}
          >
            Cancel
          </.button>
          <%= form_tag(~p"/dashboard/email", [method: :delete, id: "#{@modal_id}-form"]) do %>
            <input type="hidden" name="email" value={@email.email} />
          <% end %>
          <.button
            type="button"
            variant="danger"
            onclick={"document.getElementById('#{@modal_id}-form').submit()"}
          >
            Delete Email
          </.button>
        </:footer>
      </HexpmWeb.Components.Modal.modal>
    <% end %>
    """
  end
end
