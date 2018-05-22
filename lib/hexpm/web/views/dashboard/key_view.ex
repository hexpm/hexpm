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
end
