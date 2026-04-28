defmodule HexpmWeb.Dashboard.Email.Components.EmailOptionsCard do
  @moduledoc """
  Email options card component for the dashboard.
  Allows users to opt out of optional notification emails.
  """
  use Phoenix.Component
  use PhoenixHTMLHelpers
  import HexpmWeb.Components.Buttons
  import HexpmWeb.Components.Form, only: [sudo_form: 1]

  use Phoenix.VerifiedRoutes,
    endpoint: HexpmWeb.Endpoint,
    router: HexpmWeb.Router,
    statics: HexpmWeb.static_paths()

  attr :optional_email_types, :list, required: true
  attr :optional_email_preferences, :map, required: true
  attr :current_user, :map, required: true

  def email_options_card(assigns) do
    ~H"""
    <div class="bg-white dark:bg-grey-800 border border-grey-200 dark:border-grey-700 rounded-lg p-8">
      <h2 class="text-grey-900 dark:text-white text-xl font-semibold mb-2">
        Email Options
      </h2>

      <p class="text-sm text-grey-500 dark:text-grey-300 mb-6">
        Hex.pm always sends account-critical emails such as verification, password resets, and security alerts.
        Below are the optional emails that you can turn off.
      </p>

      <.sudo_form
        current_user={@current_user}
        action={~p"/dashboard/email/options"}
      >
        <div class="space-y-4">
          <%= for type <- @optional_email_types do %>
            <label class="flex items-start gap-3 cursor-pointer">
              <input
                type="hidden"
                name={"optional_emails[#{type.id}]"}
                value="false"
              />
              <input
                type="checkbox"
                name={"optional_emails[#{type.id}]"}
                value="true"
                checked={Map.get(@optional_email_preferences, to_string(type.id))}
                class="mt-1 h-4 w-4 rounded border-grey-300 text-primary-600 focus:ring-primary-500 dark:border-grey-600 dark:bg-grey-700"
              />
              <div>
                <span class="text-sm font-medium text-grey-900 dark:text-white">
                  {type.title}
                </span>
                <p class="text-sm text-grey-500 dark:text-grey-400">
                  {type.description}
                </p>
              </div>
            </label>
          <% end %>
        </div>

        <div class="mt-6">
          <.button type="submit" size="md">
            Save preferences
          </.button>
        </div>
      </.sudo_form>
    </div>
    """
  end
end
