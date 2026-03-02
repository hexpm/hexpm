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
    <div class="tw:bg-white tw:border tw:border-grey-200 tw:rounded-lg tw:p-8">
      <div class="tw:flex tw:items-start tw:justify-between">
        <div>
          <h2 class="tw:text-grey-900 tw:text-xl tw:font-semibold tw:mb-2">
            Two-Factor Authentication
          </h2>
          <p class="tw:text-grey-600 tw:text-sm">
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
        <div class="tw:flex tw:items-center tw:gap-2 tw:p-3 tw:bg-green-50 tw:border tw:border-green-200 tw:rounded-lg tw:mt-6">
          {icon(:heroicon, "check-circle", class: "tw:w-5 tw:h-5 tw:text-green-600")}
          <span class="tw:text-sm tw:text-green-700 tw:font-medium">
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
