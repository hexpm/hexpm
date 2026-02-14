defmodule HexpmWeb.Dashboard.Email.Components.AddEmailModal do
  @moduledoc """
  Modal for adding a new email address.
  """
  use Phoenix.Component
  use PhoenixHTMLHelpers
  import HexpmWeb.Components.Buttons
  import HexpmWeb.Components.Input

  use Phoenix.VerifiedRoutes,
    endpoint: HexpmWeb.Endpoint,
    router: HexpmWeb.Router,
    statics: HexpmWeb.static_paths()

  attr :changeset, :any, required: true

  def add_email_modal(assigns) do
    ~H"""
    <HexpmWeb.Components.Modal.modal id="add-email-modal" max_width="md">
      <:header>
        <h2 class="tw:text-lg tw:font-semibold tw:text-grey-900">
          Add New Email
        </h2>
      </:header>

      <%= form_for @changeset, ~p"/dashboard/email", [method: :post, id: "add-email-form"], fn f -> %>
        <.text_input
          field={f[:email]}
          label="Email address"
          type="email"
          placeholder="your.email@example.com"
          required
        />
      <% end %>

      <:footer>
        <.button
          type="button"
          variant="outline"
          phx-click={HexpmWeb.Components.Modal.hide_modal("add-email-modal")}
        >
          Cancel
        </.button>
        <.button type="button" onclick="document.getElementById('add-email-form').submit()">
          Add Email
        </.button>
      </:footer>
    </HexpmWeb.Components.Modal.modal>
    """
  end
end
