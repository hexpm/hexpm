defmodule HexpmWeb.Dashboard.Organization.Components.OrgTabNav do
  @moduledoc """
  Horizontal tab navigation for the organization dashboard pages.
  Renders the tab bar and, below it, the content passed as `inner_block`.
  """
  use Phoenix.Component

  alias Hexpm.Accounts.SSO

  attr :organization, :any, required: true
  attr :current_user, :any, required: true
  attr :tab, :atom, required: true

  slot :inner_block, required: true

  def org_tab_nav(assigns) do
    ~H"""
    <div>
      <div class="border-b border-grey-200 dark:border-grey-800 mb-4 sm:mb-6">
        <nav
          id="org-tab-nav"
          phx-hook="ScrollActiveIntoView"
          class="-mb-px flex gap-1 overflow-x-auto scrollbar-hide touch-pan-x"
          aria-label="Organization tabs"
        >
          <%= for {tab, label, path} <- tabs(@organization, @current_user) do %>
            <a
              href={path}
              data-active={@tab == tab && "true"}
              class={[
                "whitespace-nowrap px-3 sm:px-4 py-3 text-xs sm:text-sm font-medium border-b-2 transition-colors",
                "min-h-[44px] flex items-center gap-2",
                if(@tab == tab,
                  do:
                    "border-primary-600 dark:border-primary-300 text-primary-600 dark:text-primary-300",
                  else:
                    "border-transparent text-grey-500 dark:text-grey-300 hover:text-grey-700 dark:hover:text-grey-100 hover:border-grey-300 dark:hover:border-grey-700"
                )
              ]}
            >
              <span>{label}</span>
              <span
                :if={label == "Policies"}
                class="inline-flex items-center px-1.5 py-[2px] rounded-full text-[9px] font-bold leading-none uppercase tracking-wider bg-primary-600 text-white"
              >
                NEW
              </span>
            </a>
          <% end %>
        </nav>
      </div>

      {render_slot(@inner_block)}
    </div>
    """
  end

  defp tabs(org, current_user) do
    name = org.name

    core_tabs = [
      {:profile, "Profile", "/dashboard/orgs/#{name}"},
      {:members, "Members", "/dashboard/orgs/#{name}/members"},
      {:keys, "Keys", "/dashboard/orgs/#{name}/keys"},
      {:policies, "Policies", "/dashboard/orgs/#{name}/policies"},
      {:packages, "Packages", "/dashboard/orgs/#{name}/packages"},
      {:audit_logs, "Activity", "/dashboard/orgs/#{name}/audit-logs"},
      {:danger_zone, "Danger Zone", "/dashboard/orgs/#{name}/danger-zone"}
    ]

    if organization_admin?(org, current_user) do
      admin_tabs =
        if SSO.enabled?(org) do
          List.insert_at(core_tabs, 5, {:sso, "SSO", "/dashboard/orgs/#{name}/sso"})
        else
          core_tabs
        end

      List.insert_at(admin_tabs, 5, {:billing, "Billing", "/dashboard/orgs/#{name}/billing"})
    else
      core_tabs
    end
  end

  defp organization_admin?(org, current_user) do
    Enum.any?(org.organization_users, fn organization_user ->
      organization_user.user_id == current_user.id && organization_user.role == "admin"
    end)
  end
end
