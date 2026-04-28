defmodule HexpmWeb.Dashboard.Email.Components.AddEmailModal do
  @moduledoc """
  Modal for adding a new email address.
  """
  use Phoenix.Component
  use PhoenixHTMLHelpers
  import HexpmWeb.Components.Buttons
  import HexpmWeb.Components.Form, only: [sudo_form: 1]
  import HexpmWeb.Components.Input

  use Phoenix.VerifiedRoutes,
    endpoint: HexpmWeb.Endpoint,
    router: HexpmWeb.Router,
    statics: HexpmWeb.static_paths()

  attr :changeset, :any, required: true
  attr :current_user, :map, required: true

  def add_email_modal(assigns) do
    ~H"""
    <HexpmWeb.Components.Modal.modal id="add-email-modal" max_width="md">
      <:header>
        <h2 class="text-lg font-semibold text-grey-900">
          Add New Email
        </h2>
      </:header>

      <.sudo_form
        :let={f}
        current_user={@current_user}
        for={@changeset}
        action={~p"/dashboard/email"}
        id="add-email-form"
      >
        <.text_input
          field={f[:email]}
          label="Email address"
          type="email"
          placeholder="your.email@example.com"
          required
        />
        <div class="flex items-center justify-end gap-3 mt-6">
          <.button
            type="button"
            variant="outline"
            phx-click={HexpmWeb.Components.Modal.hide_modal("add-email-modal")}
          >
            Cancel
          </.button>
          <.button type="submit">
            Add Email
          </.button>
        </div>
      </.sudo_form>
    </HexpmWeb.Components.Modal.modal>
    """
  end
end
