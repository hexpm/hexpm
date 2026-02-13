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
  attr :csrf_token, :string, required: true
  attr :show, :boolean, default: false
  attr :error, :string, default: nil
  attr :form_action, :string, default: nil

  def tfa_setup_modal(assigns) do
    ~H"""
    <.modal id="tfa-setup-modal" title="Two-Factor Authentication Setup" max_width="2xl" show={@show}>
      <div class="tw:space-y-6">
        <%!-- Instructions --%>
        <div>
          <h3 class="tw:text-lg tw:font-semibold tw:text-grey-900 tw:mb-2">
            Scan this QR code with your authenticator app
          </h3>
          <p class="tw:text-sm tw:text-grey-600">
            Use apps like Google Authenticator, Authy, or 1Password to scan the QR code below.
          </p>
        </div>

        <%!-- QR Code --%>
        <div class="tw:flex tw:justify-center tw:p-6 tw:bg-grey-50 tw:rounded-lg tw:border tw:border-grey-200">
          <%= if @user.tfa && @user.tfa.secret do %>
            {raw(ViewHelpers.auth_qr_code_svg(@user))}
          <% else %>
            <div class="tw:text-center tw:text-grey-500">
              <p>Please enable two-factor authentication first.</p>
            </div>
          <% end %>
        </div>

        <%!-- Manual Setup Key --%>
        <%= if @user.tfa && @user.tfa.secret do %>
          <div class="tw:bg-grey-50 tw:border tw:border-grey-200 tw:rounded-lg tw:p-4">
            <p class="tw:text-sm tw:text-grey-700 tw:mb-3">
              Can't scan the QR code? Use this setup key instead:
            </p>
            <div
              id="tfa-secret"
              data-value={@user.tfa.secret}
              class="tw:flex tw:items-center tw:justify-between tw:gap-3 tw:p-3 tw:bg-white tw:border tw:border-grey-200 tw:rounded-lg"
            >
              <code class="tw:font-mono tw:text-sm tw:text-grey-900 tw:break-all">
                {@user.tfa.secret}
              </code>
              <button
                id="copy-tfa-secret-btn"
                type="button"
                phx-hook="CopyButton"
                data-copy-target="tfa-secret"
                class="tw:relative tw:flex-shrink-0 tw:p-2 tw:text-grey-500 tw:hover:text-grey-700 tw:hover:bg-grey-100 tw:rounded tw:transition-colors"
                aria-label="Copy setup key to clipboard"
              >
                {icon(:heroicon, "clipboard-document", class: "tw:w-5 tw:h-5")}
              </button>
            </div>
          </div>
        <% end %>

        <%!-- Error Message --%>
        <%= if @error == "invalid_code" do %>
          <div class="tw:flex tw:items-center tw:gap-3 tw:p-4 tw:bg-red-50 tw:border tw:border-red-200 tw:rounded-lg">
            {icon(:heroicon, "exclamation-circle",
              class: "tw:w-5 tw:h-5 tw:text-red-600 tw:flex-shrink-0"
            )}
            <div class="tw:flex-1">
              <p class="tw:text-sm tw:text-red-800 tw:font-medium">
                Incorrect verification code
              </p>
              <p class="tw:text-sm tw:text-red-700 tw:mt-1">
                Please check your authenticator app and try again. Codes refresh every 30 seconds.
              </p>
            </div>
          </div>
        <% end %>

        <%!-- Verification Form --%>
        <%= if @user.tfa && @user.tfa.secret do %>
          <form
            action={~p"/dashboard/security/verify-tfa-code"}
            method="post"
            id="tfa-verification-form"
          >
            <input type="hidden" name="_csrf_token" value={@csrf_token} />
            <div class="tw:space-y-4">
              <div>
                <label
                  for="verification_code"
                  class="tw:block tw:text-sm tw:font-medium tw:text-grey-700 tw:mb-2"
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
                  phx-hook="TFACodeValidator"
                  data-target-button="tfa-submit-btn"
                  class="tw:w-full tw:px-3 tw:py-2 tw:border tw:border-grey-300 tw:rounded-lg tw:text-center tw:text-xl tw:font-mono tw:tracking-widest tw:focus:outline-none tw:focus:ring-2 tw:focus:ring-purple-500 tw:focus:border-transparent"
                />
                <p class="tw:mt-2 tw:text-xs tw:text-grey-500">
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
          onclick="document.getElementById('tfa-verification-form').submit()"
          class="tw:opacity-50 tw:cursor-not-allowed"
        >
          Enable Two-Factor Authentication
        </.button>
      </:footer>
    </.modal>
    """
  end
end
