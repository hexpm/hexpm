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
    <div class="tw:bg-white tw:border tw:border-grey-200 tw:rounded-lg tw:p-8">
      <h2 class="tw:text-grey-900 tw:text-xl tw:font-semibold tw:mb-6">
        Password Authentication
      </h2>

      <%= if Hexpm.Accounts.User.has_password?(@user) do %>
        <%!-- Change Password Form --%>
        <%= form_for @changeset, ~p"/dashboard/security/change-password", [method: :post], fn f -> %>
          <div class="tw:space-y-5">
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

            <div class="tw:flex tw:items-center tw:gap-3 tw:pt-2">
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
            [method: :post, id: "remove-password-form", style: "display: none;"]
          ) do %>
            <button type="submit" id="remove-password-form-submit" style="display: none;"></button>
          <% end %>
        <% else %>
          <p class="tw:text-grey-500 tw:text-sm tw:mt-4 tw:p-3 tw:bg-grey-50 tw:rounded-lg">
            You must connect a GitHub account before you can remove your password.
          </p>
        <% end %>
      <% else %>
        <%!-- Add Password Form --%>
        <%= form_for @add_password_changeset, ~p"/dashboard/security/add-password", [method: :post], fn f -> %>
          <div class="tw:space-y-5">
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
