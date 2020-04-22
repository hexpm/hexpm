defmodule HexpmWeb.DashboardView do
  use HexpmWeb, :view

  defp account_settings() do
    [
      profile: {"Profile", Routes.profile_path(Endpoint, :index)},
      password: {"Password", Routes.dashboard_password_path(Endpoint, :index)},
      security: {"Security", Routes.dashboard_security_path(Endpoint, :index)},
      email: {"Emails", Routes.email_path(Endpoint, :index)},
      keys: {"Keys", Routes.key_path(Endpoint, :index)},
      audit_logs: {"Recent activities", Routes.audit_log_path(Endpoint, :index)}
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

  defp permission_name(%KeyPermission{domain: "repositories"}),
    do: "REPOS"
end
