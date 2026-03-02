defmodule HexpmWeb.Templates.Dashboard.Security.Components.AuthenticatorAppCard do
  @moduledoc """
  Authenticator app management card component.
  Allows users to reset their authenticator app setup.
  """
  use Phoenix.Component
  use PhoenixHTMLHelpers
  import HexpmWeb.Components.Buttons
  import HexpmWeb.Components.Modal, only: [show_modal: 1]
  import HexpmWeb.Components.ConfirmationModal
  use Hexpm.Shared

  use Phoenix.VerifiedRoutes,
    endpoint: HexpmWeb.Endpoint,
    router: HexpmWeb.Router,
    statics: HexpmWeb.static_paths()

  def authenticator_app_card(assigns) do
    ~H"""
    <div class="tw:bg-white tw:border tw:border-grey-200 tw:rounded-lg tw:p-8">
      <h2 class="tw:text-grey-900 tw:text-xl tw:font-semibold tw:mb-4">
        Authenticator App
      </h2>

      <p class="tw:text-grey-600 tw:text-sm tw:mb-4">
        Reset your authenticator app if you've lost access to your device. This will
        invalidate your current two-factor device and recovery codes.
      </p>

      <.button type="button" variant="outline" phx-click={show_modal("reset-auth-app-modal")}>
        Setup New App
      </.button>
    </div>

    <%!-- Reset Auth App Confirmation Modal --%>
    <.confirmation_modal
      id="reset-auth-app-modal"
      title="Reset Authenticator App?"
      message="This will disable two-factor authentication until you scan the new QR code and verify it. All your current recovery codes will stop working and new ones will be generated."
      confirm_text="Reset App"
      confirm_action={~p"/dashboard/security/reset-auth-app"}
      danger={true}
    />
    """
  end
end
