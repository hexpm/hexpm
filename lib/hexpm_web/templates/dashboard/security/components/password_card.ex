defmodule HexpmWeb.Templates.Dashboard.Security.Components.PasswordCard do
  @moduledoc """
  Password authentication card component.
  Allows users to change, add, or remove their password.
  """
  use Phoenix.Component
  use PhoenixHTMLHelpers
  import HexpmWeb.Components.Buttons
  import HexpmWeb.Components.Input
  use Hexpm.Shared

  use Phoenix.VerifiedRoutes,
    endpoint: HexpmWeb.Endpoint,
    router: HexpmWeb.Router,
    statics: HexpmWeb.static_paths()

  attr :changeset, :map, required: true
  attr :add_password_changeset, :map, required: true
  attr :user, :map, required: true

  def password_card(assigns) do
    ~H"""
    <div class="bg-white border border-grey-200 rounded-lg p-8">
      <h2 class="text-grey-900 text-xl font-semibold mb-6">
        Password Authentication
      </h2>

      <%= if Hexpm.Accounts.User.has_password?(@user) do %>
        <%!-- Change Password Form --%>
        <%= form_for @changeset, ~p"/dashboard/security/change-password", [method: :post], fn f -> %>
          <div class="space-y-5">
            <.password_input
              field={f[:password_current]}
              label="Current Password"
              placeholder="Enter your current password"
            />

            <.password_input
              field={f[:password]}
              label="New Password"
              placeholder="Enter your new password"
            />

            <.password_input
              field={f[:password_confirmation]}
              label="Confirm New Password"
              placeholder="Confirm your new password"
              match_password_id={Phoenix.HTML.Form.input_id(f, :password)}
            />

            <div class="flex items-center gap-3 pt-2">
              <.button type="submit" variant="primary">
                Change Password
              </.button>

              <%= if Hexpm.Accounts.User.can_remove_password?(@user) do %>
                <.button
                  type="button"
                  variant="danger-outline"
                  onclick="if(confirm('Are you sure you want to remove your password? You will need to use GitHub to sign in.')) { document.getElementById('remove-password-form-submit').click(); }"
                >
                  Remove Password
                </.button>
              <% end %>
            </div>
          </div>
        <% end %>

        <%= if Hexpm.Accounts.User.can_remove_password?(@user) do %>
          <%= form_tag(
            ~p"/dashboard/security/remove-password",
            [method: :post, id: "remove-password-form", class: "hidden"]
          ) do %>
            <button type="submit" id="remove-password-form-submit" class="hidden"></button>
          <% end %>
        <% else %>
          <p class="text-grey-500 text-sm mt-4 p-3 bg-grey-50 rounded-lg">
            You must connect a GitHub account before you can remove your password.
          </p>
        <% end %>
      <% else %>
        <%!-- Add Password Form --%>
        <%= form_for @add_password_changeset, ~p"/dashboard/security/add-password", [method: :post], fn f -> %>
          <div class="space-y-5">
            <.password_input
              field={f[:password]}
              label="New Password"
              placeholder="Enter your password"
            />

            <.password_input
              field={f[:password_confirmation]}
              label="Confirm Password"
              placeholder="Confirm your password"
              match_password_id={Phoenix.HTML.Form.input_id(f, :password)}
            />

            <.button type="submit" variant="primary">
              Add Password
            </.button>
          </div>
        <% end %>
      <% end %>
    </div>
    """
  end
end
