defmodule HexpmWeb.Templates.Dashboard.Security.Components.TFACard do
  @moduledoc """
  Two-Factor Authentication card component.
  Shows TFA status and enable/disable controls.
  """
  use Phoenix.Component
  use PhoenixHTMLHelpers
  import HexpmWeb.ViewIcons, only: [icon: 3]
  import HexpmWeb.Components.Buttons
  import HexpmWeb.Components.Modal, only: [show_modal: 1]
  import HexpmWeb.Components.ConfirmationModal
  use Hexpm.Shared

  use Phoenix.VerifiedRoutes,
    endpoint: HexpmWeb.Endpoint,
    router: HexpmWeb.Router,
    statics: HexpmWeb.static_paths()

  attr :user, :map, required: true

  def tfa_card(assigns) do
    ~H"""
    <div class="bg-white border border-grey-200 rounded-lg p-8">
      <div class="flex items-start justify-between">
        <div>
          <h2 class="text-grey-900 text-xl font-semibold mb-2">
            Two-Factor Authentication
          </h2>
          <p class="text-grey-600 text-sm">
            Add an extra layer of security to your account
          </p>
        </div>

        <%= if Hexpm.Accounts.User.tfa_enabled?(@user) do %>
          <.button type="button" variant="danger" phx-click={show_modal("disable-tfa-modal")}>
            Disable
          </.button>
        <% else %>
          <%= form_tag(~p"/dashboard/security/enable-tfa", [method: :post, id: "enable-tfa-form"]) do %>
            <.button type="submit" variant="primary">
              Enable
            </.button>
          <% end %>
        <% end %>
      </div>

      <%= if Hexpm.Accounts.User.tfa_enabled?(@user) do %>
        <div class="flex items-center gap-2 p-3 bg-green-50 border border-green-200 rounded-lg mt-6">
          {icon(:heroicon, "check-circle", class: "w-5 h-5 text-green-600")}
          <span class="text-sm text-green-700 font-medium">
            Two-factor authentication is enabled
          </span>
        </div>
      <% end %>
    </div>

    <%!-- Disable TFA Confirmation Modal --%>
    <.confirmation_modal
      id="disable-tfa-modal"
      title="Disable Two-Factor Authentication?"
      message="Disabling two-factor authentication will make your account less secure. You will no longer need codes from your authenticator app to sign in, and your recovery codes will be deleted."
      confirm_text="Disable Two-Factor"
      confirm_action={~p"/dashboard/security/disable-tfa"}
      danger={true}
    />
    """
  end
end
