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

  import HexpmWeb.Components.Badge, only: [badge: 1]
  import HexpmWeb.Components.Buttons, only: [button: 1, icon_button: 1]
  import HexpmWeb.Components.Form, only: [sudo_form: 1]
  import HexpmWeb.Components.Input, only: [text_input: 1, select_input: 1, toggle_switch: 1]
  import HexpmWeb.Components.Modal, only: [modal: 1, show_modal: 1, hide_modal: 1]

  attr :add_member_changeset, :any, required: true
  attr :current_user, :map, required: true
  attr :invitations, :list, default: []
  attr :invite_changeset, :any, default: nil
  attr :organization, :map, required: true
  attr :quantity, :integer, default: nil
  attr :sso_mode, :atom, default: :optional
  attr :sso_required_at, :any, default: nil

  def members_tab(assigns) do
    ~H"""
    <div class="space-y-6">
      <section
        :if={
          admin?(@current_user, @organization) &&
            Hexpm.Accounts.OrganizationTFA.configurable?(@organization)
        }
        class="rounded-lg border border-grey-200 dark:border-grey-700 bg-white dark:bg-grey-800 p-6 space-y-4"
      >
        <h2 class="text-lg font-semibold">Require two-factor authentication</h2>
        <p>
          Members must enable two-factor authentication on their accounts. After the deadline, members without 2FA lose access to the organization until they enable it. SSO settings are separate.
        </p>
        <p :if={@organization.tfa_required_at}>
          Enforcement deadline: <strong>{HexpmWeb.ViewHelpers.pretty_utc_datetime(@organization.tfa_required_at)}</strong>.
          Suspended members retain their membership, role, package ownership, and billed seat.
        </p>
        <p :if={!@organization.tfa_required_at}>Enforcement is disabled.</p>
        <.sudo_form
          current_user={@current_user}
          action={~p"/dashboard/orgs/#{@organization}/tfa"}
          id="organization-tfa-policy"
          class="group/tfa-policy space-y-4"
        >
          <.select_input
            id="policy-enforcement"
            name="policy[enforcement]"
            label="Enforcement"
            options={tfa_enforcement_options(@organization)}
            value={if @organization.tfa_required_at, do: "keep", else: "transition"}
          />
          <div
            :if={!Hexpm.Accounts.OrganizationTFA.enforced?(@organization)}
            id="policy-grace-days"
            class="hidden group-has-[option[value=transition]:checked]/tfa-policy:block"
          >
            <.text_input
              id="policy-grace-days-input"
              type="number"
              name="policy[grace_days]"
              label="Days from now until enforcement (1 to 30)"
              value="14"
              min="1"
              max="30"
            />
          </div>
          <p>
            Configuring this policy requires 2FA on your own account. Once enforcement starts, disable it before scheduling another transition.
          </p>
          <.button type="submit">Save 2FA policy</.button>
        </.sudo_form>
      </section>
      <%!-- Member List --%>
      <div class="bg-white dark:bg-grey-800 border border-grey-200 dark:border-grey-700 rounded-lg overflow-hidden">
        <div class="px-6 py-5 border-b border-grey-200 dark:border-grey-700 flex flex-col items-start gap-4 sm:flex-row sm:items-center sm:justify-between">
          <div>
            <h2 class="text-grey-900 dark:text-white text-lg font-semibold">Members</h2>
            <p class="text-grey-500 dark:text-grey-300 text-sm mt-1">
              <% count = member_count(@organization) %>
              <%= if @quantity do %>
                {count} of {@quantity} seats in use
              <% else %>
                {count} {member_label(count)}
              <% end %>
            </p>
          </div>
          <%= if admin?(@current_user, @organization) do %>
            <div class="flex flex-wrap items-center gap-2">
              <.button
                variant="outline"
                size="sm"
                class="border-dashed"
                phx-click={show_modal(invite_modal_id())}
              >
                {HexpmWeb.ViewIcons.icon(:heroicon, "envelope", class: "w-4 h-4")} Invite by email
              </.button>
              <.button
                variant="outline"
                size="sm"
                class="border-dashed"
                phx-click={show_modal(add_member_modal_id())}
              >
                {HexpmWeb.ViewIcons.icon(:heroicon, "plus", class: "w-4 h-4")} Add member
              </.button>
            </div>
          <% end %>
        </div>

        <p
          :if={
            admin?(@current_user, @organization) and @sso_mode == :pilot and
              not is_nil(@sso_required_at)
          }
          id="sso-required-date"
          class="px-6 py-3 border-b border-grey-200 dark:border-grey-700 bg-grey-50 dark:bg-grey-900 text-sm text-grey-600 dark:text-grey-300"
        >
          SSO becomes required on
          <strong class="font-semibold text-grey-900 dark:text-white">
            {HexpmWeb.ViewHelpers.pretty_date(@sso_required_at)}
          </strong>
          for every member who isn't exempt. Until then only the members with Require SSO turned on need it.
        </p>

        <ul class="divide-y divide-grey-100 dark:divide-grey-700">
          <%= for org_user <- @organization.organization_users do %>
            <li class="flex flex-col items-start gap-3 px-6 py-4 sm:flex-row sm:items-center sm:justify-between">
              <%!-- Avatar + name --%>
              <div class="flex min-w-0 items-center gap-3">
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
                  <p class="flex flex-wrap items-center gap-2 text-sm font-medium text-grey-900 dark:text-white">
                    <a
                      href={~p"/users/#{org_user.user}"}
                      class="hover:text-primary-600 transition-colors"
                    >
                      {org_user.user.username}
                    </a>
                    <.badge
                      :if={
                        admin?(@current_user, @organization) and @sso_mode != :optional and
                          org_user.sso_enforcement == "exempt"
                      }
                      variant="yellow"
                    >
                      SSO exempt
                    </.badge>
                  </p>
                  <p class="text-xs text-grey-500 dark:text-grey-300">{org_user.user.full_name}</p>
                  <p
                    :if={admin?(@current_user, @organization)}
                    class="text-xs text-grey-600 dark:text-grey-300"
                  >
                    {case Hexpm.Accounts.OrganizationTFA.enrollment_status(
                            @organization,
                            org_user.user
                          ) do
                      "enabled" -> "2FA enabled"
                      "overdue" -> "2FA enrollment overdue"
                      "pending" -> "2FA enrollment pending"
                    end}
                  </p>
                </div>
              </div>

              <%!-- Actions --%>
              <div class="flex shrink-0 flex-wrap items-center gap-2">
                <%= if admin?(@current_user, @organization) do %>
                  <.sudo_form
                    :if={@sso_mode == :pilot}
                    current_user={@current_user}
                    action={~p"/dashboard/orgs/#{@organization}/sso/enforcement/member"}
                    id={"sso-enforcement-form-#{org_user.user.id}"}
                    class="flex items-center gap-2"
                    phx-hook="AutoSubmit"
                  >
                    <input type="hidden" name="user_id" value={org_user.user.id} />
                    <label
                      for={"sso-enforcement-#{org_user.user.id}"}
                      class="text-sm text-grey-600 dark:text-grey-300"
                    >
                      Require SSO
                    </label>
                    <.toggle_switch
                      id={"sso-enforcement-#{org_user.user.id}"}
                      name="sso_enforcement"
                      value="enforced"
                      hidden_value=""
                      checked={org_user.sso_enforcement == "enforced"}
                    />
                  </.sudo_form>

                  <%!-- Role select (auto-submits on change) --%>
                  <.sudo_form
                    current_user={@current_user}
                    action={~p"/dashboard/orgs/#{@organization}"}
                    id={"change-role-form-#{org_user.user.id}"}
                    phx-hook="AutoSubmit"
                  >
                    <input type="hidden" name="action" value="change_role" />
                    <input
                      type="hidden"
                      name="organization_user[username]"
                      value={org_user.user.username}
                    />
                    <.select_input
                      id={"role-#{org_user.user.id}"}
                      name="organization_user[role]"
                      value={org_user.role}
                      options={role_options()}
                      variant="light"
                      size="sm"
                      class="w-28"
                    />
                  </.sudo_form>

                  <%!-- Remove member --%>
                  <%= if org_user.user.id != @current_user.id do %>
                    <.icon_button
                      icon="x-mark"
                      variant="danger"
                      aria-label="Remove member"
                      phx-click={show_modal("remove-member-#{org_user.user.id}")}
                    />
                  <% else %>
                    <span class="hidden sm:block w-8 h-8" aria-hidden="true"></span>
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

      <%!-- Exemptions. A required organization's exemption list is the set of
      accounts reaching private packages on a Hexpm password alone, so it is
      presented as the compliance surface it is rather than as a settings row. --%>
      <div
        :if={admin?(@current_user, @organization) and @sso_mode != :optional}
        class="bg-white dark:bg-grey-800 border border-grey-200 dark:border-grey-700 rounded-lg overflow-hidden"
      >
        <% {exempt, exemptable} = partition_exempt(@organization) %>
        <div class="px-6 py-5 border-b border-grey-200 dark:border-grey-700">
          <h2 class="text-grey-900 dark:text-white text-lg font-semibold">
            Exempt from SSO
          </h2>
          <p class="text-grey-500 dark:text-grey-300 text-sm mt-1">
            {exemption_summary(exempt, @sso_mode == :required or not is_nil(@sso_required_at))}
          </p>
          <.sudo_form
            :if={exemptable != []}
            current_user={@current_user}
            action={~p"/dashboard/orgs/#{@organization}/sso/enforcement/member"}
            id="sso-exempt-form"
            class="mt-4 flex flex-wrap items-center gap-2"
          >
            <input type="hidden" name="sso_enforcement" value="exempt" />
            <.select_input
              id="sso-exempt-user"
              name="user_id"
              options={Enum.map(exemptable, &{&1.user.username, &1.user.id})}
              prompt="Choose a member"
              required
              variant="light"
              size="sm"
            />
            <.button type="submit" variant="outline" size="sm">Exempt</.button>
          </.sudo_form>
        </div>

        <ul :if={exempt != []} class="divide-y divide-grey-100 dark:divide-grey-700">
          <li
            :for={org_user <- exempt}
            class="flex flex-col items-start gap-3 px-6 py-4 sm:flex-row sm:items-center sm:justify-between"
          >
            <div>
              <p class="text-sm font-medium text-grey-900 dark:text-white">
                {org_user.user.username}
              </p>
              <p class="text-xs text-grey-500 dark:text-grey-300">
                {String.capitalize(org_user.role)} access without authenticating through your provider
              </p>
            </div>
            <.sudo_form
              current_user={@current_user}
              action={~p"/dashboard/orgs/#{@organization}/sso/enforcement/member"}
              id={"sso-unexempt-form-#{org_user.user.id}"}
            >
              <input type="hidden" name="user_id" value={org_user.user.id} />
              <input type="hidden" name="sso_enforcement" value="" />
              <.button type="submit" variant="outline" size="sm">Remove exemption</.button>
            </.sudo_form>
          </li>
        </ul>
      </div>

      <%!-- Pending invitations (admin only, hidden when there are none) --%>
      <div
        :if={admin?(@current_user, @organization) and @invitations != []}
        class="bg-white dark:bg-grey-800 border border-grey-200 dark:border-grey-700 rounded-lg overflow-hidden"
      >
        <div class="px-6 py-5 border-b border-grey-200 dark:border-grey-700">
          <h2 class="text-grey-900 dark:text-white text-lg font-semibold">Pending invitations</h2>
          <p class="text-grey-500 dark:text-grey-300 text-sm mt-1">
            A seat is taken when an invitation is accepted, not when it is sent.
          </p>
        </div>

        <ul class="divide-y divide-grey-100 dark:divide-grey-700">
          <li :for={invitation <- @invitations} class="flex items-center justify-between px-6 py-4">
            <div>
              <p class="text-sm font-medium text-grey-900 dark:text-white">{invitation.email}</p>
              <p class="text-xs text-grey-500 dark:text-grey-300">
                Invited as {invitation.role}, expires {Calendar.strftime(
                  invitation.expires_at,
                  "%Y-%m-%d"
                )}
              </p>
            </div>

            <div class="flex items-center gap-2">
              <.sudo_form
                current_user={@current_user}
                action={~p"/dashboard/orgs/#{@organization}"}
                id={"revoke-invitation-form-#{invitation.id}"}
              >
                <input type="hidden" name="action" value="revoke_invitation" />
                <input type="hidden" name="organization_invitation[id]" value={invitation.id} />
                <.icon_button icon="x-mark" variant="danger" aria-label="Revoke invitation" />
              </.sudo_form>
            </div>
          </li>
        </ul>
      </div>

      <%!-- Remove member confirmation modals (one per removable member) --%>
      <%= if admin?(@current_user, @organization) do %>
        <%= for org_user <- @organization.organization_users, org_user.user.id != @current_user.id do %>
          <.modal id={"remove-member-#{org_user.user.id}"} title="Remove member?" max_width="sm">
            <p class="text-sm text-grey-600 dark:text-grey-300">
              Are you sure you want to remove
              <strong class="font-semibold text-grey-900 dark:text-white">
                {org_user.user.username}
              </strong>
              from <strong class="font-semibold text-grey-900 dark:text-white">{@organization.name}</strong>?
              They will lose access to all private packages.
            </p>

            <:footer>
              <.button
                type="button"
                variant="secondary"
                phx-click={hide_modal("remove-member-#{org_user.user.id}")}
              >
                Cancel
              </.button>
              <.sudo_form
                current_user={@current_user}
                action={~p"/dashboard/orgs/#{@organization}"}
                id={"remove-member-form-#{org_user.user.id}"}
              >
                <input type="hidden" name="action" value="remove_member" />
                <input
                  type="hidden"
                  name="organization_user[username]"
                  value={org_user.user.username}
                />
                <.button type="submit" variant="danger">
                  Remove member
                </.button>
              </.sudo_form>
            </:footer>
          </.modal>
        <% end %>
      <% end %>

      <%!-- Add Member modal (admin only) --%>
      <%= if admin?(@current_user, @organization) do %>
        <.modal id={add_member_modal_id()} title="Add member" max_width="sm">
          <div class="px-1">
            <p class="text-sm text-grey-500 dark:text-grey-300 mb-6">
              Add an existing Hex user to your organization.
            </p>

            <.sudo_form
              :let={f}
              current_user={@current_user}
              for={@add_member_changeset}
              action={~p"/dashboard/orgs/#{@organization}"}
            >
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
            </.sudo_form>
          </div>
        </.modal>
      <% end %>
      <%!-- Invite by email modal (admin only) --%>
      <%= if admin?(@current_user, @organization) do %>
        <.modal id={invite_modal_id()} title="Invite by email" max_width="sm">
          <div class="px-1">
            <p class="text-sm text-grey-500 dark:text-grey-300 mb-6">
              Send an invitation to someone who is not a member yet. They accept with their own Hex
              account, creating one first if they need to, and the seat is taken then.
            </p>

            <.sudo_form
              :let={f}
              current_user={@current_user}
              for={@invite_changeset}
              as={:organization_invitation}
              action={~p"/dashboard/orgs/#{@organization}"}
            >
              <input type="hidden" name="action" value="invite_member" />
              <div class="space-y-4">
                <.text_input
                  field={f[:email]}
                  label="Email address"
                  placeholder="person@example.com"
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
                <.button type="button" variant="secondary" phx-click={hide_modal(invite_modal_id())}>
                  Cancel
                </.button>
                <.button type="submit" variant="primary">
                  Send invitation
                </.button>
              </div>
            </.sudo_form>
          </div>
        </.modal>
      <% end %>
    </div>
    """
  end

  defp tfa_enforcement_options(organization) do
    keep = if organization.tfa_required_at, do: [{"Keep current deadline", "keep"}], else: []

    schedule =
      if Hexpm.Accounts.OrganizationTFA.enforced?(organization),
        do: [],
        else: [{"Schedule a transition", "transition"}, {"Enforce immediately", "immediate"}]

    keep ++ schedule ++ [{"Disable enforcement", "disabled"}]
  end

  defp add_member_modal_id, do: "add-member-modal"

  defp invite_modal_id, do: "invite-member-modal"

  defp role_options, do: [{"Read", "read"}, {"Write", "write"}, {"Admin", "admin"}]

  defp admin?(current_user, organization) do
    Enum.any?(organization.organization_users, fn ou ->
      ou.user_id == current_user.id && ou.role == "admin"
    end)
  end

  defp member_count(organization), do: length(organization.organization_users)

  defp member_label(1), do: "member"
  defp member_label(_), do: "members"

  defp reach_label(1), do: "reaches"
  defp reach_label(_), do: "reach"

  defp role_badge_class("admin"), do: "bg-purple-100 text-purple-700"
  defp role_badge_class("write"), do: "bg-blue-100 text-blue-700"
  defp role_badge_class(_), do: "bg-grey-100 text-grey-600"

  defp partition_exempt(organization) do
    organization.organization_users
    |> Enum.sort_by(& &1.user.username)
    |> Enum.split_with(&(&1.sso_enforcement == "exempt"))
  end

  # A pilot without a required-by date governs nobody it has not been told to,
  # so an exemption there only takes effect once SSO becomes required.
  defp exemption_summary([], true = _requires_sso?) do
    "Nobody is exempt. Every member authenticates through your provider to reach this organization in a browser or with the CLI. Organization API keys and, unless you block them, personal API keys still reach it without authenticating."
  end

  defp exemption_summary(exempt, true = _requires_sso?) do
    count = length(exempt)

    "#{count} #{member_label(count)} #{reach_label(count)} this organization's private packages on a Hexpm password alone. This list bounds what SSO enforcement can claim, so keep it short and review it."
  end

  defp exemption_summary([], false = _requires_sso?) do
    "Nobody is exempt. Once SSO is required, every member authenticates through your provider to reach this organization."
  end

  defp exemption_summary(exempt, false = _requires_sso?) do
    count = length(exempt)

    "#{count} #{member_label(count)} will keep reaching this organization's private packages on a Hexpm password alone once SSO is required."
  end
end
