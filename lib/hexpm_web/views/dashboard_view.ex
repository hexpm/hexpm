defmodule HexpmWeb.DashboardView do
  use HexpmWeb, :view

  defp account_settings() do
    [
      profile: {"Profile", ~p"/dashboard/profile"},
      password: {"Password", ~p"/dashboard/password"},
      security: {"Security", ~p"/dashboard/security"},
      email: {"Emails", ~p"/dashboard/email"},
      keys: {"Keys", ~p"/dashboard/keys"},
      audit_logs: {"Recent activities", ~p"/dashboard/audit-logs"}
    ]
  end

  defp selected_setting(conn, id) do
    if Enum.take(conn.path_info, -2) == ["dashboard", Atom.to_string(id)] do
      "selected"
    end
  end

  defp selected_organization(conn, name) do
    if Enum.take(conn.path_info, -2) == ["orgs", name] do
      "selected"
    end
  end

  defp permission_name(%KeyPermission{domain: "api", resource: nil}),
    do: "API"

  defp permission_name(%KeyPermission{domain: "api", resource: resource}),
    do: "API:#{resource}"

  defp permission_name(%KeyPermission{domain: "repository", resource: resource}),
    do: "REPO:#{resource}"

  defp permission_name(%KeyPermission{domain: "package", resource: "hexpm/" <> resource}),
    do: "PKG:#{resource}"

  defp permission_name(%KeyPermission{domain: "package", resource: resource}),
    do: "PKG:#{resource}"

  defp permission_name(%KeyPermission{domain: "repositories"}),
    do: "REPOS"
end
