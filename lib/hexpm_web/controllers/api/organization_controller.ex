defmodule HexpmWeb.API.OrganizationController do
  use HexpmWeb, :controller
  alias Hexpm.Billing

  plug :fetch_organization

  plug :authorize,
       [domains: [{"api", "read"}]]
       when action == :index

  plug :authorize,
       [domains: [{"api", "read"}], fun: {AuthHelpers, :organization_access}]
       when action in [:show, :audit_logs]

  plug :authorize,
       [
         domains: [{"api", "write"}],
         fun: {AuthHelpers, :organization_access, [organization_level: "write"]}
       ]
       when action == :update

  def index(conn, _params) do
    organizations =
      all_organizations_by_user(conn.assigns.current_user) ++
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

  @not_enough_seats "number of seats cannot be less than number of members"

  def update(conn, %{"organization" => name} = params) do
    organization = Organizations.get(name)
    seats = safe_to_integer(params["seats"])

    if seats do
      result =
        Seats.update_quantity(organization, seats, fn quantity ->
          Hexpm.Billing.update(organization.name, %{"quantity" => quantity})
        end)

      case result do
        {:ok, customer} ->
          conn
          |> api_cache(:private)
          |> render(:show, organization: organization, customer: customer)

        {:error, {:seats_below_members, _used}} ->
          validation_failed(conn, @not_enough_seats)
      end
    else
      validation_failed(conn, @not_enough_seats)
    end
  end

  def audit_logs(conn, params) do
    organization = conn.assigns.organization
    audit_logs = AuditLogs.all_by(organization, Hexpm.Utils.safe_int(params["page"]), 100)

    render(conn, :audit_logs, audit_logs: audit_logs)
  end

  defp current_organization(nil), do: []
  defp current_organization(organization), do: [organization]

  defp all_organizations_by_user(%User{} = user), do: Organizations.all_by_user(user)
  defp all_organizations_by_user(nil = _user), do: []
end
