defmodule HexpmWeb.Templates.Dashboard.Security.Components.ConnectedAccountsCard do
  @moduledoc """
  Connected accounts card component for the security dashboard.
  Shows OAuth provider connections (e.g., GitHub).
  """
  use Phoenix.Component
  use PhoenixHTMLHelpers
  import HexpmWeb.Components.Buttons
  import HexpmWeb.Components.Icons, only: [github_icon: 1]
  use Hexpm.Shared

  use Phoenix.VerifiedRoutes,
    endpoint: HexpmWeb.Endpoint,
    router: HexpmWeb.Router,
    statics: HexpmWeb.static_paths()

  attr :user, :map, required: true

  def connected_accounts_card(assigns) do
    ~H"""
    <div class="tw:bg-white tw:border tw:border-grey-200 tw:rounded-lg tw:p-8">
      <h2 class="tw:text-grey-900 tw:text-xl tw:font-semibold tw:mb-6">
        Connected Accounts
      </h2>

      <%!-- GitHub Connection --%>
      <div class="tw:flex tw:items-start tw:gap-4">
        <div class="tw:flex-shrink-0 tw:w-12 tw:h-12 tw:bg-grey-100 tw:rounded-lg tw:flex tw:items-center tw:justify-center">
          <.github_icon class="tw:w-6 tw:h-6 tw:text-grey-700" />
        </div>

        <div class="tw:flex-1">
          <h3 class="tw:text-grey-900 tw:font-medium tw:mb-1">
            GitHub
          </h3>

          <%= if Hexpm.Accounts.UserProviders.has_provider?(@user, "github") do %>
            <p class="tw:text-grey-600 tw:text-sm tw:mb-4">
              Your GitHub account is connected. You can sign in using GitHub.
            </p>
            <%= form_tag(~p"/dashboard/security/disconnect-github", [method: :post]) do %>
              <.button type="submit" variant="danger" size="sm">
                Disconnect
              </.button>
            <% end %>
          <% else %>
            <p class="tw:text-grey-600 tw:text-sm tw:mb-4">
              Connect your GitHub account to enable GitHub login.
            </p>
            <.button_link href={~p"/auth/github"} variant="primary" size="sm">
              Connect GitHub
            </.button_link>
          <% end %>
        </div>
      </div>
    </div>
    """
  end
end
