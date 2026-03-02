defmodule HexpmWeb.Templates.Dashboard.Security.Components.RecoveryCodesCard do
  @moduledoc """
  Recovery codes management card component.
  Displays recovery codes and allows generating new ones.
  """
  use Phoenix.Component
  use PhoenixHTMLHelpers
  import HexpmWeb.Components.Buttons
  alias Hexpm.Accounts.User
  use Hexpm.Shared

  use Phoenix.VerifiedRoutes,
    endpoint: HexpmWeb.Endpoint,
    router: HexpmWeb.Router,
    statics: HexpmWeb.static_paths()

  attr :user, :map, required: true

  def recovery_codes_card(assigns) do
    ~H"""
    <div class="tw:bg-white tw:border tw:border-grey-200 tw:rounded-lg tw:p-8">
      <h2 class="tw:text-grey-900 tw:text-xl tw:font-semibold tw:mb-4">
        Recovery Codes
      </h2>

      <p class="tw:text-grey-600 tw:text-sm tw:mb-6">
        Recovery codes can be used to access your account in the event you lose access to
        your device and cannot receive two-factor authentication codes.
      </p>

      <%= if show_recovery_codes?(@user) do %>
        <%!-- Recovery Codes Display --%>
        <div
          class="tw:p-6 tw:bg-grey-50 tw:border tw:border-grey-200 tw:rounded-lg tw:mb-6"
          id="recovery-codes"
          data-value={aggregate_recovery_codes(@user.tfa.recovery_codes)}
        >
          <div class="tw:grid tw:grid-cols-2 tw:gap-3">
            <%= for code <- @user.tfa.recovery_codes do %>
              <div class="tw:flex tw:items-center tw:justify-between tw:p-2 tw:bg-white tw:rounded tw:border tw:border-grey-200">
                <code class={[
                  "tw:text-sm tw:font-mono",
                  if(code.used_at,
                    do: "tw:text-grey-400 tw:line-through",
                    else: "tw:text-grey-900"
                  )
                ]}>
                  {code.code}
                </code>
                <%= if code.used_at do %>
                  <span class="tw:text-xs tw:px-2 tw:py-1 tw:bg-grey-100 tw:text-grey-600 tw:rounded">
                    Used
                  </span>
                <% end %>
              </div>
            <% end %>
          </div>
        </div>

        <%!-- Action Buttons --%>
        <div class="tw:flex tw:items-center tw:gap-3 tw:mb-8">
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
      <div class="tw:border-t tw:border-grey-200 tw:pt-6">
        <h3 class="tw:text-grey-900 tw:font-medium tw:mb-2">
          Generate New Recovery Codes
        </h3>
        <p class="tw:text-grey-600 tw:text-sm tw:mb-4">
          When you generate new recovery codes, you must download or print the new codes.
          Your old codes won't work anymore.
        </p>

        <%= form_tag(~p"/dashboard/security/rotate-recovery-codes", [method: :post]) do %>
          <.button type="submit" variant="outline">
            Generate New Codes
          </.button>
        <% end %>
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
