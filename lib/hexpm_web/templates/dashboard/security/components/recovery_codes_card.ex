defmodule HexpmWeb.Templates.Dashboard.Security.Components.RecoveryCodesCard do
  @moduledoc """
  Recovery codes management card component.
  Links to the recovery codes page and allows generating new ones.
  """
  use Phoenix.Component
  use PhoenixHTMLHelpers
  import HexpmWeb.Components.Buttons
  import HexpmWeb.Components.Form, only: [sudo_form: 1]
  use Hexpm.Shared

  use Phoenix.VerifiedRoutes,
    endpoint: HexpmWeb.Endpoint,
    router: HexpmWeb.Router,
    statics: HexpmWeb.static_paths()

  attr :user, :map, required: true

  def recovery_codes_card(assigns) do
    ~H"""
    <div class="bg-white dark:bg-grey-800 border border-grey-200 dark:border-grey-700 rounded-lg p-8">
      <h2 class="text-grey-900 dark:text-white text-xl font-semibold mb-4">
        Recovery Codes
      </h2>

      <p class="text-grey-600 dark:text-grey-300 text-sm mb-4">
        Recovery codes can be used to access your account in the event you lose access to
        your device and cannot receive two-factor authentication codes.
      </p>

      <p class="text-grey-600 dark:text-grey-300 text-sm mb-4">
        {unused_count(@user)} of {length(@user.tfa.recovery_codes)} codes unused
      </p>

      <.button_link variant="outline" href={~p"/dashboard/security/recovery-codes"}>
        View Recovery Codes
      </.button_link>

      <%!-- Generate New Codes Section --%>
      <div class="border-t border-grey-200 dark:border-grey-700 mt-8 pt-6">
        <h3 class="text-grey-900 dark:text-white font-medium mb-2">
          Generate New Recovery Codes
        </h3>
        <p class="text-grey-600 dark:text-grey-300 text-sm mb-4">
          When you generate new recovery codes, you must download or print the new codes.
          Your old codes won't work anymore.
        </p>

        <.sudo_form current_user={@user} action={~p"/dashboard/security/rotate-recovery-codes"}>
          <.button type="submit" variant="outline">
            Generate New Codes
          </.button>
        </.sudo_form>
      </div>
    </div>
    """
  end

  defp unused_count(user), do: Enum.count(user.tfa.recovery_codes, &is_nil(&1.used_at))
end
