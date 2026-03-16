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
    <div class="bg-white border border-grey-200 rounded-lg p-8">
      <h2 class="text-grey-900 text-xl font-semibold mb-6">
        Connected Accounts
      </h2>

      <%!-- GitHub Connection --%>
      <div class="flex items-start gap-4">
        <div class="flex-shrink-0 w-12 h-12 bg-grey-100 rounded-lg flex items-center justify-center">
          <.github_icon class="w-6 h-6 text-grey-700" />
        </div>

        <div class="flex-1">
          <h3 class="text-grey-900 font-medium mb-1">
            GitHub
          </h3>

          <%= if Hexpm.Accounts.UserProviders.has_provider?(@user, "github") do %>
            <p class="text-grey-600 text-sm mb-4">
              Your GitHub account is connected. You can sign in using GitHub.
            </p>
            <%= form_tag(~p"/dashboard/security/disconnect-github", [method: :post]) do %>
              <.button type="submit" variant="danger" size="sm">
                Disconnect
              </.button>
            <% end %>
          <% else %>
            <p class="text-grey-600 text-sm mb-4">
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
