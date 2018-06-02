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

  def formatted_used_at(nil),
    do: "never"

  def formatted_used_at(%{year: year, month: month, day: day, hour: hour, minute: minute, second: second}) do
    "#{day |> zero_pad}/#{month |> zero_pad}/#{year |> zero_pad} " <>
    "#{hour |> zero_pad}:#{minute |> zero_pad}:#{second |> zero_pad}"
  end

  defp zero_pad(number) do
    number
    |> Integer.to_string
    |> String.pad_leading(2, "0")
  end
end
