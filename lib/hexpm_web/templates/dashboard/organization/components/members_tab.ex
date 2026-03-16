defmodule HexpmWeb.Dashboard.Organization.Components.MembersTab do
  @moduledoc """
  Members tab content for the organization dashboard.
  Handles member listing, role changes, and adding new members.
  """
  use Phoenix.Component
  use PhoenixHTMLHelpers
  use Hexpm.Shared

  use Phoenix.VerifiedRoutes,
    endpoint: HexpmWeb.Endpoint,
    router: HexpmWeb.Router,
    statics: HexpmWeb.static_paths()

  import HexpmWeb.Components.Buttons, only: [button: 1, icon_button: 1]
  import HexpmWeb.Components.Input, only: [text_input: 1, select_input: 1]
  import HexpmWeb.Components.Modal, only: [modal: 1, show_modal: 1, hide_modal: 1]

  attr :add_member_changeset, :any, required: true
  attr :current_user, :map, required: true
  attr :organization, :map, required: true
  attr :quantity, :integer, default: nil

  def members_tab(assigns) do
    ~H"""
    <div class="space-y-6">
      <%!-- Member List --%>
      <div class="bg-white border border-grey-200 rounded-lg overflow-hidden">
        <div class="px-6 py-5 border-b border-grey-200 flex items-center justify-between">
          <div>
            <h2 class="text-grey-900 text-lg font-semibold">Members</h2>
            <p class="text-grey-500 text-sm mt-1">
              <% count = member_count(@organization) %>
              <%= if @quantity do %>
                {count} of {@quantity} seats in use
              <% else %>
                {count} {member_label(count)}
              <% end %>
            </p>
          </div>
          <%= if admin?(@current_user, @organization) do %>
            <.button
              variant="outline"
              size="sm"
              class="border-dashed"
              phx-click={show_modal(add_member_modal_id())}
            >
              {HexpmWeb.ViewIcons.icon(:heroicon, "plus", class: "w-4 h-4")} Add member
            </.button>
          <% end %>
        </div>

        <ul class="divide-y divide-grey-100">
          <%= for org_user <- @organization.organization_users do %>
            <li class="flex items-center justify-between px-6 py-4">
              <%!-- Avatar + name --%>
              <div class="flex items-center gap-3">
                <img
                  src={
                    HexpmWeb.ViewHelpers.gravatar_url(
                      Hexpm.Accounts.User.email(org_user.user, :gravatar),
                      :small
                    )
                  }
                  alt={org_user.user.username}
                  class="w-9 h-9 rounded-full flex-shrink-0"
                />
                <div>
                  <p class="text-sm font-medium text-grey-900">
                    <a
                      href={~p"/users/#{org_user.user}"}
                      class="hover:text-primary-600 transition-colors"
                    >
                      {org_user.user.username}
                    </a>
                  </p>
                  <p class="text-xs text-grey-500">{org_user.user.full_name}</p>
                </div>
              </div>

              <%!-- Actions --%>
              <div class="flex items-center gap-2">
                <%= if admin?(@current_user, @organization) do %>
                  <%!-- Role select (auto-submits on change) --%>
                  <%= form_for :organization_user, ~p"/dashboard/orgs/#{@organization}", [method: :post, onchange: "this.submit()"], fn _f -> %>
                    <input type="hidden" name="action" value="change_role" />
                    <input
                      type="hidden"
                      name="organization_user[username]"
                      value={org_user.user.username}
                    />
                    <.select_input
                      id={"role-#{org_user.user.username}"}
                      name="organization_user[role]"
                      value={org_user.role}
                      options={role_options()}
                      variant="light"
                      class="w-28 h-9 text-sm"
                    />
                  <% end %>

                  <%!-- Remove (hidden for self) --%>
                  <%= if org_user.user.id != @current_user.id do %>
                    <.icon_button
                      icon="x-mark"
                      variant="danger"
                      aria-label="Remove member"
                      phx-click={show_modal("remove-member-#{org_user.user.username}")}
                    />
                  <% end %>
                <% else %>
                  <span class={[
                    "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium",
                    role_badge_class(org_user.role)
                  ]}>
                    {String.capitalize(org_user.role)}
                  </span>
                <% end %>
              </div>
            </li>
          <% end %>
        </ul>
      </div>

      <%!-- Remove member confirmation modals (one per removable member) --%>
      <%= if admin?(@current_user, @organization) do %>
        <%= for org_user <- @organization.organization_users, org_user.user.id != @current_user.id do %>
          <.modal id={"remove-member-#{org_user.user.username}"} title="Remove member?" max_width="sm">
            <p class="text-sm text-grey-600">
              Are you sure you want to remove
              <strong class="font-semibold text-grey-900">{org_user.user.username}</strong>
              from <strong class="font-semibold text-grey-900">{@organization.name}</strong>?
              They will lose access to all private packages.
            </p>

            <:footer>
              <.button
                type="button"
                variant="secondary"
                phx-click={hide_modal("remove-member-#{org_user.user.username}")}
              >
                Cancel
              </.button>
              <%= form_for :organization_user, ~p"/dashboard/orgs/#{@organization}", [method: :post, id: "remove-member-form-#{org_user.user.username}"], fn _f -> %>
                <input type="hidden" name="action" value="remove_member" />
                <input
                  type="hidden"
                  name="organization_user[username]"
                  value={org_user.user.username}
                />
                <.button type="submit" variant="danger">
                  Remove member
                </.button>
              <% end %>
            </:footer>
          </.modal>
        <% end %>
      <% end %>

      <%!-- Add Member modal (admin only) --%>
      <%= if admin?(@current_user, @organization) do %>
        <.modal id={add_member_modal_id()} title="Add member" max_width="sm">
          <div class="px-1">
            <p class="text-sm text-grey-500 mb-6">
              Add an existing Hex user to your organization.
            </p>

            <%= form_for @add_member_changeset, ~p"/dashboard/orgs/#{@organization}", [method: :post], fn f -> %>
              <input type="hidden" name="action" value="add_member" />
              <div class="space-y-4">
                <.text_input
                  field={f[:username]}
                  label="Username"
                  placeholder="hex username or email address"
                  required
                />
                <.select_input
                  field={f[:role]}
                  label="Role"
                  options={role_options()}
                  variant="light"
                />
              </div>
              <div class="flex justify-end gap-3 mt-6">
                <.button
                  type="button"
                  variant="secondary"
                  phx-click={hide_modal(add_member_modal_id())}
                >
                  Cancel
                </.button>
                <.button type="submit" variant="primary">
                  Add member
                </.button>
              </div>
            <% end %>
          </div>
        </.modal>
      <% end %>
    </div>
    """
  end

  defp add_member_modal_id, do: "add-member-modal"

  defp role_options, do: [{"Read", "read"}, {"Write", "write"}, {"Admin", "admin"}]

  defp admin?(current_user, organization) do
    Enum.any?(organization.organization_users, fn ou ->
      ou.user_id == current_user.id && ou.role == "admin"
    end)
  end

  defp member_count(organization), do: length(organization.organization_users)

  defp member_label(1), do: "member"
  defp member_label(_), do: "members"

  defp role_badge_class("admin"), do: "bg-purple-100 text-purple-700"
  defp role_badge_class("write"), do: "bg-blue-100 text-blue-700"
  defp role_badge_class(_), do: "bg-grey-100 text-grey-600"
end
