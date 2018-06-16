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

  def formatted_usage_info(%Key{last_used_at: nil, last_ip: nil, last_user_agent: nil}),
    do: "never"

  def formatted_usage_info(%Key{last_used_at: timestamp, last_ip: ip, last_user_agent: user_agent}) do
    [formatted_used_at(timestamp), ip, user_agent]
    |> Enum.filter(&(&1))
    |> Enum.filter(&(String.length(&1) > 0))
    |> Enum.join(", ")
  end

  defp formatted_used_at(%{year: year, month: month, day: day, hour: hour, minute: minute, second: second}) do
    "#{year |> zero_pad}-#{month |> zero_pad}-#{day |> zero_pad}"
  end

  defp zero_pad(number) do
    number
    |> Integer.to_string
    |> String.pad_leading(2, "0")
  end
end
