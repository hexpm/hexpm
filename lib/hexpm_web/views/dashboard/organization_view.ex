defmodule HexpmWeb.Dashboard.OrganizationView do
  use HexpmWeb, :view
  alias HexpmWeb.DashboardView

  import HexpmWeb.Dashboard.Organization.Components.AuditLogsTab, only: [audit_logs_tab: 1]
  import HexpmWeb.Dashboard.Organization.Components.BillingTab, only: [billing_tab: 1]
  import HexpmWeb.Dashboard.Organization.Components.DangerZoneTab, only: [danger_zone_tab: 1]
  import HexpmWeb.Dashboard.Organization.Components.KeysTab, only: [keys_tab: 1]
  import HexpmWeb.Dashboard.Organization.Components.MembersTab, only: [members_tab: 1]
  import HexpmWeb.Dashboard.Organization.Components.OrgTabNav, only: [org_tab_nav: 1]
  import HexpmWeb.Dashboard.Organization.Components.PackagesTab, only: [packages_tab: 1]
  import HexpmWeb.Dashboard.Organization.Components.ProfileTab, only: [profile_tab: 1]
end
