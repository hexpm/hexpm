defmodule HexpmWeb.Templates.Dashboard.Security.Components.TFASetupModal do
  @moduledoc """
  Two-Factor Authentication setup modal component.
  Displays QR code and verification input for completing 2FA setup.
  """
  use Phoenix.Component
  use PhoenixHTMLHelpers
  import Phoenix.HTML, only: [raw: 1]
  import HexpmWeb.ViewIcons, only: [icon: 3]
  import HexpmWeb.Components.Modal
  import HexpmWeb.Components.Buttons, only: [button: 1]
  alias HexpmWeb.ViewHelpers
  use Hexpm.Shared

  use Phoenix.VerifiedRoutes,
    endpoint: HexpmWeb.Endpoint,
    router: HexpmWeb.Router,
    statics: HexpmWeb.static_paths()

  @doc """
  Renders the TFA setup modal with QR code and verification form.

  ## Examples

      <.tfa_setup_modal user={@current_user} csrf_token={@csrf_token} show={true} />
  """
  attr :user, :map, required: true
  attr :tfa_secret, :string, default: nil
  attr :csrf_token, :string, required: true
  attr :show, :boolean, default: false
  attr :error, :string, default: nil
  attr :form_action, :string, default: nil

  def tfa_setup_modal(assigns) do
    ~H"""
    <.modal id="tfa-setup-modal" title="Two-Factor Authentication Setup" max_width="2xl" show={@show}>
      <div class="space-y-6">
        <%!-- Instructions --%>
        <div>
          <h3 class="text-lg font-semibold text-grey-900 mb-2">
            Scan this QR code with your authenticator app
          </h3>
          <p class="text-sm text-grey-600">
            Use apps like Google Authenticator, Authy, or 1Password to scan the QR code below.
          </p>
        </div>

        <%!-- QR Code --%>
        <div class="flex justify-center p-6 bg-grey-50 rounded-lg border border-grey-200">
          <%= if @tfa_secret do %>
            {raw(ViewHelpers.auth_qr_code_svg(@user, @tfa_secret))}
          <% else %>
            <div class="text-center text-grey-500">
              <p>Please enable two-factor authentication first.</p>
            </div>
          <% end %>
        </div>

        <%!-- Manual Setup Key --%>
        <%= if @tfa_secret do %>
          <div class="bg-grey-50 border border-grey-200 rounded-lg p-4">
            <p class="text-sm text-grey-700 mb-3">
              Can't scan the QR code? Use this setup key instead:
            </p>
            <div
              id="tfa-secret"
              data-value={@tfa_secret}
              class="flex items-center justify-between gap-3 p-3 bg-white border border-grey-200 rounded-lg"
            >
              <code class="font-mono text-sm text-grey-900 break-all">
                {@tfa_secret}
              </code>
              <button
                id="copy-tfa-secret-btn"
                type="button"
                phx-hook="CopyButton"
                data-copy-target="tfa-secret"
                class="relative flex-shrink-0 p-2 text-grey-500 hover:text-grey-700 hover:bg-grey-100 rounded transition-colors"
                aria-label="Copy setup key to clipboard"
              >
                {icon(:heroicon, "clipboard-document", class: "w-5 h-5")}
              </button>
            </div>
          </div>
        <% end %>

        <%!-- Error Message --%>
        <%= if @error == "invalid_code" do %>
          <div class="flex items-center gap-3 p-4 bg-red-50 border border-red-200 rounded-lg">
            {icon(:heroicon, "exclamation-circle", class: "w-5 h-5 text-red-600 flex-shrink-0")}
            <div class="flex-1">
              <p class="text-sm text-red-800 font-medium">
                Incorrect verification code
              </p>
              <p class="text-sm text-red-700 mt-1">
                Please check your authenticator app and try again. Codes refresh every 30 seconds.
              </p>
            </div>
          </div>
        <% end %>

        <%!-- Verification Form --%>
        <%= if @tfa_secret do %>
          <form
            action={~p"/dashboard/security/verify-tfa-code"}
            method="post"
            id="tfa-verification-form"
          >
            <input type="hidden" name="_csrf_token" value={@csrf_token} />
            <div class="space-y-4">
              <div>
                <label
                  for="verification_code"
                  class="block text-sm font-medium text-grey-700 mb-2"
                >
                  Enter the 6-digit code from your app
                </label>
                <input
                  type="text"
                  id="verification_code"
                  name="verification_code"
                  placeholder="000000"
                  required
                  maxlength="6"
                  pattern="[0-9]{6}"
                  autocomplete="off"
                  inputmode="numeric"
                  oninput="document.getElementById('tfa-submit-btn').disabled = !/^[0-9]{6}$/.test(this.value)"
                  class="w-full px-3 py-2 border border-grey-300 rounded-lg text-center text-xl font-mono tracking-widest focus:outline-none focus:ring-2 focus:ring-purple-500 focus:border-transparent"
                />
                <p class="mt-2 text-xs text-grey-500">
                  The code refreshes every 30 seconds
                </p>
              </div>
            </div>
          </form>
        <% end %>
      </div>

      <:footer>
        <.button
          type="button"
          variant="secondary"
          phx-click={hide_modal("tfa-setup-modal")}
        >
          Cancel
        </.button>
        <.button
          id="tfa-submit-btn"
          type="button"
          variant="primary"
          disabled
          onclick="document.getElementById('tfa-verification-form').submit()"
        >
          Enable Two-Factor Authentication
        </.button>
      </:footer>
    </.modal>
    """
  end
end
