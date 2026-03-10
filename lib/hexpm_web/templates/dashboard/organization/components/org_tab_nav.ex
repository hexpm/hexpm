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
      <div class="tw:border-b tw:border-grey-200 tw:mb-6">
        <nav class="tw:-mb-px tw:flex tw:gap-1 tw:overflow-x-auto" aria-label="Organization tabs">
          <%= for {label, path, _active?} = tab <- tabs(@organization, @current_user) do %>
            <a
              href={path}
              class={[
                "tw:whitespace-nowrap tw:px-4 tw:py-3 tw:text-sm tw:font-medium tw:border-b-2 tw:transition-colors",
                if(active?(@conn, tab),
                  do: "tw:border-purple-600 tw:text-purple-600",
                  else:
                    "tw:border-transparent tw:text-grey-500 tw:hover:text-grey-700 tw:hover:border-grey-300"
                )
              ]}
            >
              {label}
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
      {"Profile", "/dashboard/orgs/#{name}",
       &(&1 == "/dashboard/orgs/#{name}")},
      {"Members", "/dashboard/orgs/#{name}/members",
       &String.starts_with?(&1, "/dashboard/orgs/#{name}/members")},
      {"Keys", "/dashboard/orgs/#{name}/keys",
       &String.starts_with?(&1, "/dashboard/orgs/#{name}/keys")},
      {"Packages", "/dashboard/orgs/#{name}/packages",
       &String.starts_with?(&1, "/dashboard/orgs/#{name}/packages")},
      {"Audit Logs", "/dashboard/orgs/#{name}/audit-logs",
       &String.starts_with?(&1, "/dashboard/orgs/#{name}/audit-logs")},
      {"Danger Zone", "/dashboard/orgs/#{name}/danger-zone",
       &String.starts_with?(&1, "/dashboard/orgs/#{name}/danger-zone")}
    ]

    if organization_admin?(org, current_user) do
      billing_tab = {"Billing", "/dashboard/orgs/#{name}/billing",
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
