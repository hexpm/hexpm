defmodule HexpmWeb.Dashboard.Organization.Components.OrgTabNav do
  @moduledoc """
  Horizontal tab navigation for the organization dashboard pages.
  Renders the tab bar and, below it, the content passed as `inner_block`.
  """
  use Phoenix.Component

  attr :conn, :any, required: true
  attr :organization, :any, required: true
  attr :current_user, :any, required: true

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
          <%= for {label, path, _active?} = tab <- tabs(@organization, @current_user) do %>
            <a
              href={path}
              data-active={active?(@conn, tab) && "true"}
              class={[
                "whitespace-nowrap px-3 sm:px-4 py-3 text-xs sm:text-sm font-medium border-b-2 transition-colors",
                "min-h-[44px] flex items-center gap-2",
                if(active?(@conn, tab),
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
      {"Profile", "/dashboard/orgs/#{name}", &(&1 == "/dashboard/orgs/#{name}")},
      {"Members", "/dashboard/orgs/#{name}/members",
       &String.starts_with?(&1, "/dashboard/orgs/#{name}/members")},
      {"Keys", "/dashboard/orgs/#{name}/keys",
       &String.starts_with?(&1, "/dashboard/orgs/#{name}/keys")},
      {"Policies", "/dashboard/orgs/#{name}/policies",
       &String.starts_with?(&1, "/dashboard/orgs/#{name}/policies")},
      {"Packages", "/dashboard/orgs/#{name}/packages",
       &String.starts_with?(&1, "/dashboard/orgs/#{name}/packages")},
      {"Activity", "/dashboard/orgs/#{name}/audit-logs",
       &String.starts_with?(&1, "/dashboard/orgs/#{name}/audit-logs")},
      {"Danger Zone", "/dashboard/orgs/#{name}/danger-zone",
       &String.starts_with?(&1, "/dashboard/orgs/#{name}/danger-zone")}
    ]

    if organization_admin?(org, current_user) do
      billing_tab =
        {"Billing", "/dashboard/orgs/#{name}/billing",
         &(String.starts_with?(&1, "/dashboard/orgs/#{name}/billing") or
             String.starts_with?(&1, "/dashboard/orgs/#{name}/invoices"))}

      List.insert_at(core_tabs, 5, billing_tab)
    else
      core_tabs
    end
  end

  defp active?(conn, {_label, _path, matcher}), do: matcher.(conn.request_path)

  defp organization_admin?(org, current_user) do
    Enum.any?(org.organization_users, fn organization_user ->
      organization_user.user_id == current_user.id && organization_user.role == "admin"
    end)
  end
end
