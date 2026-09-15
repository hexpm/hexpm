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
        Set up a replacement authenticator app. Your current authenticator and recovery codes
        remain active until you verify the replacement.
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
      message="Your current authenticator and recovery codes remain active until you verify the new app. After verification, the new app and recovery codes replace them."
      confirm_text="Reset App"
      confirm_action={~p"/dashboard/security/reset-auth-app"}
      danger={true}
    />
    """
  end
end
