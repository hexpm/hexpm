defmodule HexpmWeb.DashboardView do
  use HexpmWeb, :view
  import HexpmWeb.ViewIcons

  defp account_settings() do
    [
      profile: {"Profile", Routes.profile_path(Endpoint, :index)},
      security: {"Security", Routes.dashboard_security_path(Endpoint, :index)},
      email: {"Emails", Routes.email_path(Endpoint, :index)},
      keys: {"Keys", Routes.key_path(Endpoint, :index)},
      audit_logs: {"Recent activities", Routes.audit_log_path(Endpoint, :index)}
    ]
  end

  defp account_settings_icon(:profile) do
    icon(:remixicon, :"user-smile-line", width: "20px", class: "mr-2 fill-current")
  end

  defp account_settings_icon(:security) do
    icon(:remixicon, :"shield-keyhole-line", width: "20px", class: "mr-2 fill-current")
  end

  defp account_settings_icon(:keys) do
    icon(:remixicon, :"key-2-line", width: "20px", class: "mr-2 fill-current")
  end

  defp account_settings_icon(:email) do
    icon(:remixicon, :"mail-open-line", width: "20px", class: "mr-2 fill-current")
  end

  defp account_settings_icon(:audit_logs) do
    icon(:remixicon, :"time-line", width: "20px", class: "mr-2 fill-current")
  end

  defp selected_setting(conn, id) do
    if Enum.take(conn.path_info, -2) == ["dashboard", Atom.to_string(id)] do
      "text-blue-600 "
    else
      "text-gray-500"
    end
  end

  defp selected_organization(conn, name) do
    if Enum.take(conn.path_info, -2) == ["orgs", name] do
      "text-blue-600 "
    else
      "text-gray-500"
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
