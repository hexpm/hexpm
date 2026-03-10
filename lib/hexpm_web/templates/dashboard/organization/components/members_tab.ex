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

  def members_tab(assigns) do
    ~H"""
    <div class="tw:space-y-6">
      <%!-- Member List --%>
      <div class="tw:bg-white tw:border tw:border-grey-200 tw:rounded-lg tw:overflow-hidden">
        <div class="tw:px-6 tw:py-5 tw:border-b tw:border-grey-200 tw:flex tw:items-center tw:justify-between">
          <div>
            <h2 class="tw:text-grey-900 tw:text-lg tw:font-semibold">Members</h2>
            <p class="tw:text-grey-500 tw:text-sm tw:mt-1">
              <% count = member_count(@organization) %>
              {count} {member_label(count)}
            </p>
          </div>
          <%= if admin?(@current_user, @organization) do %>
            <.button
              variant="outline"
              size="sm"
              class="tw:border-dashed"
              phx-click={show_modal(add_member_modal_id())}
            >
              {HexpmWeb.ViewIcons.icon(:heroicon, "plus", class: "tw:w-4 tw:h-4")}
              Add member
            </.button>
          <% end %>
        </div>

        <ul class="tw:divide-y tw:divide-grey-100">
          <%= for org_user <- @organization.organization_users do %>
            <li class="tw:flex tw:items-center tw:justify-between tw:px-6 tw:py-4">
              <%!-- Avatar + name --%>
              <div class="tw:flex tw:items-center tw:gap-3">
                <img
                  src={HexpmWeb.ViewHelpers.gravatar_url(Hexpm.Accounts.User.email(org_user.user, :gravatar), :small)}
                  alt={org_user.user.username}
                  class="tw:w-9 tw:h-9 tw:rounded-full tw:flex-shrink-0"
                />
                <div>
                  <p class="tw:text-sm tw:font-medium tw:text-grey-900">{org_user.user.username}</p>
                  <p class="tw:text-xs tw:text-grey-500">{org_user.user.full_name}</p>
                </div>
              </div>

              <%!-- Actions --%>
              <div class="tw:flex tw:items-center tw:gap-2">
                <%= if admin?(@current_user, @organization) do %>
                  <%!-- Role select (auto-submits on change) --%>
                  <%= form_for :organization_user, ~p"/dashboard/orgs/#{@organization}", [method: :post, onchange: "this.submit()"], fn _f -> %>
                    <input type="hidden" name="action" value="change_role" />
                    <input type="hidden" name="organization_user[username]" value={org_user.user.username} />
                    <.select_input
                      id={"role-#{org_user.user.username}"}
                      name="organization_user[role]"
                      value={org_user.role}
                      options={role_options()}
                      variant="light"
                      class="tw:w-28 tw:h-9 tw:text-sm"
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
                    "tw:inline-flex tw:items-center tw:px-2.5 tw:py-0.5 tw:rounded-full tw:text-xs tw:font-medium",
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
            <p class="tw:text-sm tw:text-grey-600">
              Are you sure you want to remove
              <strong class="tw:font-semibold tw:text-grey-900">{org_user.user.username}</strong>
              from <strong class="tw:font-semibold tw:text-grey-900">{@organization.name}</strong>?
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
                <input type="hidden" name="organization_user[username]" value={org_user.user.username} />
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
          <div class="tw:px-1">
            <p class="tw:text-sm tw:text-grey-500 tw:mb-6">
              Add an existing Hex user to your organization.
            </p>

            <%= form_for @add_member_changeset, ~p"/dashboard/orgs/#{@organization}", [method: :post], fn f -> %>
              <input type="hidden" name="action" value="add_member" />
              <div class="tw:space-y-4">
                <.text_input
                  field={f[:username]}
                  label="Username"
                  placeholder="hex username"
                  required
                />
                <.select_input
                  field={f[:role]}
                  label="Role"
                  options={role_options()}
                  variant="light"
                />
              </div>
              <div class="tw:flex tw:justify-end tw:gap-3 tw:mt-6">
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

  defp role_badge_class("admin"), do: "tw:bg-purple-100 tw:text-purple-700"
  defp role_badge_class("write"), do: "tw:bg-blue-100 tw:text-blue-700"
  defp role_badge_class(_), do: "tw:bg-grey-100 tw:text-grey-600"
end
