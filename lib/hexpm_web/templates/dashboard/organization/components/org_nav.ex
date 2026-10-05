defmodule HexpmWeb.Dashboard.Organization.Components.OrgNav do
  @moduledoc """
  Sidebar navigation for the organization dashboard pages, grouped by area.
  It replaces the account settings in the dashboard sidebar on those pages.
  """
  use Phoenix.Component

  use Phoenix.VerifiedRoutes,
    endpoint: HexpmWeb.Endpoint,
    router: HexpmWeb.Router,
    statics: HexpmWeb.static_paths()

  import HexpmWeb.Components.Dropdown, only: [dropdown: 1, dropdown_item: 1]

  alias Hexpm.Accounts.SSO
  alias Hexpm.TrustedPublishers

  @new_sections [:trusted_publishers, :policies, :sso]

  attr :current_user, :map, required: true
  attr :organization, :map, required: true
  attr :tab, :atom, required: true

  def org_nav(assigns) do
    assigns =
      assigns
      |> assign(:groups, groups(assigns.organization, assigns.current_user))
      |> assign(:other_organizations, other_organizations(assigns))

    ~H"""
    <a
      href={~p"/dashboard/profile"}
      class="flex w-fit items-center gap-2 text-grey-600 dark:text-grey-300 text-sm mb-6 hover:text-grey-900 dark:hover:text-white"
    >
      {HexpmWeb.ViewIcons.icon(:heroicon, "arrow-left", class: "w-4 h-4")} Back to settings
    </a>

    <div class="flex items-center gap-3 mb-8">
      {HexpmWeb.ViewIcons.icon(:heroicon, "building-office-2",
        class: "w-8 h-8 shrink-0 text-grey-500 dark:text-grey-400"
      )}
      <div class="min-w-0">
        <p class="text-grey-600 dark:text-grey-300 text-xs font-semibold uppercase tracking-wider">
          Organization
        </p>
        <h1 class="text-grey-900 dark:text-grey-100 text-3xl font-semibold break-words">
          {@organization.name}
        </h1>
        <.dropdown
          :if={@other_organizations != []}
          id="organization-switcher"
          label="Switch organization"
          align="left"
          button_class="mt-1 flex items-center gap-1 text-sm text-grey-600 dark:text-grey-300 hover:text-grey-900 dark:hover:text-white"
        >
          <.dropdown_item
            :for={organization <- @other_organizations}
            href={~p"/dashboard/orgs/#{organization}"}
          >
            {organization.name}
          </.dropdown_item>
        </.dropdown>
      </div>
    </div>

    <div id="org-nav" class="space-y-6">
      <div :for={{label, sections} <- @groups}>
        <h3 class="text-grey-600 dark:text-grey-300 text-xs font-semibold uppercase tracking-wider mb-3">
          {label}
        </h3>
        <ul class="space-y-1">
          <li :for={{section, name, path} <- sections}>
            <a
              href={path}
              data-active={@tab == section && "true"}
              class={[
                "flex items-center gap-3 px-3 py-2 rounded-lg text-sm transition-colors",
                if(@tab == section,
                  do:
                    "bg-purple-50 dark:bg-primary-900/40 text-purple-600 dark:text-primary-200 font-medium",
                  else: "text-grey-600 dark:text-grey-300 hover:text-grey-900 dark:hover:text-white"
                )
              ]}
            >
              <span>{name}</span>
              <span
                :if={section in new_sections()}
                class="ml-auto inline-flex items-center px-1.5 py-[2px] rounded-full text-[9px] font-bold leading-none uppercase tracking-wider bg-primary-600 text-white"
              >
                NEW
              </span>
            </a>
          </li>
        </ul>
      </div>

      <div class="border-t border-grey-200 dark:border-grey-700 pt-4">
        <a
          href={~p"/dashboard/orgs/#{@organization}/danger-zone"}
          data-active={@tab == :danger_zone && "true"}
          class={[
            "flex items-center gap-3 px-3 py-2 rounded-lg text-sm transition-colors",
            if(@tab == :danger_zone,
              do: "bg-red-50 dark:bg-red-950 text-red-700 dark:text-red-300 font-medium",
              else: "text-red-700 dark:text-red-400 hover:text-red-800 dark:hover:text-red-300"
            )
          ]}
        >
          Danger Zone
        </a>
      </div>
    </div>
    """
  end

  defp new_sections, do: @new_sections

  defp groups(organization, current_user) do
    admin? = organization_admin?(organization, current_user)

    [
      {"General",
       [
         {:profile, "Profile", ~p"/dashboard/orgs/#{organization}"},
         {:members, "Members", ~p"/dashboard/orgs/#{organization}/members"}
       ] ++
         if(admin?,
           do: [{:billing, "Billing", ~p"/dashboard/orgs/#{organization}/billing"}],
           else: []
         ) ++
         [{:audit_logs, "Activity", ~p"/dashboard/orgs/#{organization}/audit-logs"}]},
      {"Access",
       [{:keys, "Keys", ~p"/dashboard/orgs/#{organization}/keys"}] ++
         if(TrustedPublishers.enabled?(),
           do: [
             {:trusted_publishers, "Trusted publishers",
              ~p"/dashboard/orgs/#{organization}/trusted-publishers"}
           ],
           else: []
         ) ++
         if(admin? and SSO.reachable?(organization),
           do: [{:sso, "SSO", ~p"/dashboard/orgs/#{organization}/sso"}],
           else: []
         )},
      {"Packages",
       [
         {:packages, "Packages", ~p"/dashboard/orgs/#{organization}/packages"},
         {:policies, "Policies", ~p"/dashboard/orgs/#{organization}/policies"}
       ]}
    ]
  end

  defp other_organizations(%{current_user: current_user, organization: organization}) do
    current_user.organizations
    |> Enum.reject(&(&1.id == organization.id))
    |> Enum.sort_by(& &1.name)
  end

  defp organization_admin?(organization, current_user) do
    Enum.any?(organization.organization_users, fn organization_user ->
      organization_user.user_id == current_user.id && organization_user.role == "admin"
    end)
  end
end
