defmodule Hexpm.Web.Dashboard.KeyView do
  use Hexpm.Web, :view
  alias Hexpm.Web.DashboardView

  def permission_name(%KeyPermission{domain: "api", resource: nil}),
    do: "API"

  def permission_name(%KeyPermission{domain: "api", resource: resource}),
    do: "API:#{resource}"

  def permission_name(%KeyPermission{domain: "repository", resource: resource}),
    do: "ORG:#{resource}"

  def permission_name(%KeyPermission{domain: "repositories"}),
    do: "ORGS"

  def formatted_usage_info(%Key{last_use: nil}),
    do: "never"

  def formatted_usage_info(%Key{last_use: last_use}) do
    [formatted_used_at(last_use.used_at), last_use.ip, last_use.user_agent]
    |> Enum.filter(& &1)
    |> Enum.filter(&(String.length(&1) > 0))
    |> Enum.join(" ")
  end

  defp formatted_used_at(datetime) do
    datetime
    |> NaiveDateTime.to_date()
    |> Date.to_string()
  end
end
