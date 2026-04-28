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

  attr :user, :map, required: true

  def authenticator_app_card(assigns) do
    ~H"""
    <div class="bg-white dark:bg-grey-800 border border-grey-200 dark:border-grey-700 rounded-lg p-8">
      <h2 class="text-grey-900 dark:text-white text-xl font-semibold mb-4">
        Authenticator App
      </h2>

      <p class="text-grey-600 dark:text-grey-300 text-sm mb-4">
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
      current_user={@user}
      title="Reset Authenticator App?"
      message="This will disable two-factor authentication until you scan the new QR code and verify it. All your current recovery codes will stop working and new ones will be generated."
      confirm_text="Reset App"
      confirm_action={~p"/dashboard/security/reset-auth-app"}
      danger={true}
    />
    """
  end
end
