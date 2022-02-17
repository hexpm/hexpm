defmodule HexpmWeb.API.OrganizationController do
  use HexpmWeb, :controller
  alias Hexpm.Billing

  plug :fetch_organization

  plug :authorize,
       [domain: "api", resource: "read"]
       when action == :index

  plug :authorize,
       [domain: "api", resource: "read", fun: &organization_access/2]
       when action in [:show, :audit_logs]

  plug :authorize,
       [
         domain: "api",
         resource: "write",
         fun: &organization_access/3,
         opts: [organization_level: "write"]
       ]
       when action == :update

  def index(conn, _params) do
    organizations =
      Organizations.all_by_user(conn.assigns.current_user) ++
        current_organization(conn.assigns.current_organization)

    conn
    |> api_cache(:private)
    |> render(:index, organizations: organizations)
  end

  def show(conn, %{"organization" => name}) do
    organization = Organizations.get(name)
    customer = Billing.get(name)

    conn
    |> api_cache(:private)
    |> render(:show, organization: organization, customer: customer)
  end

  def update(conn, %{"organization" => name} = params) do
    organization = Organizations.get(name)
    user_count = Organizations.user_count(organization)

    if params["seats"] >= user_count do
      {:ok, customer} = Hexpm.Billing.update(organization.name, %{"quantity" => params["seats"]})

      conn
      |> api_cache(:private)
      |> render(:show, organization: organization, customer: customer)
    else
      validation_failed(conn, "number of seats cannot be less than number of members")
    end
  end

  def audit_logs(conn, params) do
    organization = conn.assigns.organization
    audit_logs = AuditLogs.all_by(organization, Hexpm.Utils.safe_int(params["page"]), 100)

    render(conn, :audit_logs, audit_logs: audit_logs)
  end

  defp current_organization(nil), do: []
  defp current_organization(organization), do: [organization]
end
