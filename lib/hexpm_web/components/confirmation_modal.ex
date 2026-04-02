defmodule HexpmWeb.Components.ConfirmationModal do
  @moduledoc """
  Reusable confirmation modal for destructive or important actions.

  ## Examples

      <.confirmation_modal
        id="delete-user-modal"
        title="Delete User?"
        message="This action cannot be undone. All user data will be permanently deleted."
        confirm_text="Delete User"
        confirm_action={~p"/admin/users/\#{@user.id}/delete"}
        danger={true}
      />
      
      # Trigger the modal:
      <.button phx-click={show_modal("delete-user-modal")}>Delete</.button>
  """
  use Phoenix.Component
  use PhoenixHTMLHelpers
  import HexpmWeb.Components.Modal, only: [modal: 1, hide_modal: 1]
  import HexpmWeb.Components.Buttons

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :message, :string, required: true
  attr :confirm_text, :string, default: "Confirm"
  attr :cancel_text, :string, default: "Cancel"
  attr :confirm_action, :string, required: true
  attr :danger, :boolean, default: true

  def confirmation_modal(assigns) do
    ~H"""
    <.modal id={@id} max_width="md">
      <%!-- Header with Icon --%>
      <:header>
        <h2 class="text-lg font-semibold text-grey-900">
          {@title}
        </h2>
      </:header>

      <%!-- Message --%>
      <p class="text-grey-700">
        {@message}
      </p>

      <%!-- Footer with Actions --%>
      <:footer>
        <.button type="button" variant="outline" phx-click={hide_modal(@id)}>
          {@cancel_text}
        </.button>
        <%= form_tag(@confirm_action, [method: :post, class: "m-0"]) do %>
          <.button
            type="submit"
            variant={if @danger, do: "danger", else: "primary"}
          >
            {@confirm_text}
          </.button>
        <% end %>
      </:footer>
    </.modal>
    """
  end
end
