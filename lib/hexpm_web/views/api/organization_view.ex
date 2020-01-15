defmodule HexpmWeb.API.OrganizationView do
  use HexpmWeb, :view
  alias HexpmWeb.API.OrganizationUserView

  def render("index." <> _, %{organizations: organizations}) do
    Enum.map(organizations, fn organization ->
      %{
        name: organization.name,
        billing_active: organization.billing_active,
        inserted_at: organization.inserted_at,
        updated_at: organization.updated_at
      }
    end)
  end

  def render("show." <> _, %{organization: organization, customer: customer}) do
    %{
      name: organization.name,
      billing_active: organization.billing_active,
      inserted_at: organization.inserted_at,
      updated_at: organization.updated_at,
      seats: customer["quantity"]
    }
    |> ViewHelpers.include_if_loaded(
      :users,
      organization.organization_users,
      OrganizationUserView,
      "show"
    )
  end

  def render("audit_logs." <> _, %{audit_logs: audit_logs}) do
    render_many(audit_logs, HexpmWeb.API.AuditLogView, "show")
  end
end
