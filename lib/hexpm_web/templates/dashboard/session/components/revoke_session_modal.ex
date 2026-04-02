defmodule HexpmWeb.Dashboard.Session.Components.RevokeSessionModal do
  @moduledoc """
  Modal for revoking a session with confirmation.
  """
  use Phoenix.Component
  use PhoenixHTMLHelpers
  import HexpmWeb.Components.Buttons

  use Phoenix.VerifiedRoutes,
    endpoint: HexpmWeb.Endpoint,
    router: HexpmWeb.Router,
    statics: HexpmWeb.static_paths()

  attr :session, :map, required: true

  def revoke_session_modal(assigns) do
    modal_id = "revoke-session-#{assigns.session.id}"
    session_type = if assigns.session.type == "browser", do: "browser", else: "OAuth"
    assigns = assign(assigns, modal_id: modal_id, session_type: session_type)

    ~H"""
    <HexpmWeb.Components.Modal.modal id={@modal_id} max_width="md">
      <:header>
        <h2 class="text-lg font-semibold text-grey-900">
          Revoke {@session_type} Session?
        </h2>
      </:header>

      <p class="text-grey-700">
        Are you sure you want to revoke the session <strong>{@session.name || "Unnamed session"}</strong>?
      </p>

      <%= if @session.type == "oauth" and @session.client do %>
        <p class="text-grey-700 mt-2">
          This will revoke access for <strong>{@session.client.name}</strong>.
        </p>
      <% end %>

      <p class="text-grey-600 text-small mt-3">
        This action cannot be undone. You will need to sign in again or re-authorize the application.
      </p>

      <:footer>
        <.button
          type="button"
          variant="outline"
          phx-click={HexpmWeb.Components.Modal.hide_modal(@modal_id)}
        >
          Cancel
        </.button>
        <%= form_tag(~p"/dashboard/sessions", [method: :delete, id: "#{@modal_id}-form"]) do %>
          <input type="hidden" name="_id" value={@session.id} />
          <.button type="submit" variant="danger">
            Revoke Session
          </.button>
        <% end %>
      </:footer>
    </HexpmWeb.Components.Modal.modal>
    """
  end
end
