defmodule HexpmWeb.Templates.Dashboard.Security.Components.RecoveryCodesCard do
  @moduledoc """
  Recovery codes management card component.
  Displays recovery codes and allows generating new ones.
  """
  use Phoenix.Component
  use PhoenixHTMLHelpers
  import HexpmWeb.Components.Buttons
  import HexpmWeb.Components.Form, only: [sudo_form: 1]
  alias Hexpm.Accounts.User
  use Hexpm.Shared

  use Phoenix.VerifiedRoutes,
    endpoint: HexpmWeb.Endpoint,
    router: HexpmWeb.Router,
    statics: HexpmWeb.static_paths()

  attr :user, :map, required: true

  def recovery_codes_card(assigns) do
    ~H"""
    <div class="bg-white border border-grey-200 rounded-lg p-8">
      <h2 class="text-grey-900 text-xl font-semibold mb-4">
        Recovery Codes
      </h2>

      <p class="text-grey-600 text-sm mb-6">
        Recovery codes can be used to access your account in the event you lose access to
        your device and cannot receive two-factor authentication codes.
      </p>

      <%= if show_recovery_codes?(@user) do %>
        <%!-- Recovery Codes Display --%>
        <div
          class="p-6 bg-grey-50 border border-grey-200 rounded-lg mb-6"
          id="recovery-codes"
          data-value={aggregate_recovery_codes(@user.tfa.recovery_codes)}
        >
          <div class="grid grid-cols-2 gap-3">
            <%= for code <- @user.tfa.recovery_codes do %>
              <div class="flex items-center justify-between p-2 bg-white rounded border border-grey-200">
                <code class={[
                  "text-sm font-mono",
                  if(code.used_at,
                    do: "text-grey-400 line-through",
                    else: "text-grey-900"
                  )
                ]}>
                  {code.code}
                </code>
                <%= if code.used_at do %>
                  <span class="text-xs px-2 py-1 bg-grey-100 text-grey-600 rounded">
                    Used
                  </span>
                <% end %>
              </div>
            <% end %>
          </div>
        </div>

        <%!-- Action Buttons --%>
        <div class="flex items-center gap-3 mb-8">
          <.button
            id="download-recovery-codes-btn"
            type="button"
            variant="outline"
            size="sm"
            phx-hook="DownloadButton"
            data-download-target="recovery-codes"
          >
            Download
          </.button>
          <.button
            id="print-recovery-codes-btn"
            type="button"
            variant="outline"
            size="sm"
            phx-hook="PrintButton"
            data-print-target="recovery-codes"
          >
            Print
          </.button>
          <.button
            id="copy-recovery-codes-btn"
            type="button"
            variant="outline"
            size="sm"
            phx-hook="CopyButton"
            data-copy-target="recovery-codes"
          >
            Copy
          </.button>
        </div>
      <% end %>

      <%!-- Generate New Codes Section --%>
      <div class="border-t border-grey-200 pt-6">
        <h3 class="text-grey-900 font-medium mb-2">
          Generate New Recovery Codes
        </h3>
        <p class="text-grey-600 text-sm mb-4">
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

  defp show_recovery_codes?(user) do
    User.tfa_enabled?(user) && user.tfa.recovery_codes
  end

  defp aggregate_recovery_codes(codes) do
    codes
    |> Enum.map(& &1.code)
    |> Enum.reduce(fn code, acc -> acc <> "\n" <> code end)
  end
end
