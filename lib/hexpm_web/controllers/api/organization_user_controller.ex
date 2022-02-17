defmodule HexpmWeb.API.OrganizationUserController do
  use HexpmWeb, :controller

  plug :fetch_organization

  plug :authorize,
       [domain: "api", resource: "read", fun: &organization_access/2]
       when action in [:index, :show]

  plug :authorize,
       [
         domain: "api",
         resource: "write",
         fun: &organization_access/3,
         opts: [organization_role: "admin"]
       ]
       when action in [:create, :update, :delete]

  def index(conn, %{"organization" => name}) do
    organization = Organizations.get(name, users: :emails)

    conn
    |> api_cache(:private)
    |> render(:index, organization_users: organization.organization_users)
  end

  def show(conn, %{"organization" => name, "name" => username}) do
    organization = Organizations.get(name)
    user = Users.public_get(username, [:emails])
    role = user && Organizations.get_role(organization, user)

    if role do
      conn
      |> api_cache(:private)
      |> render(:show, user: user, role: role)
    else
      not_found(conn)
    end
  end

  def create(conn, %{"organization" => name, "name" => username} = params) do
    organization = Organizations.get(name)
    user_count = Organizations.user_count(organization)
    customer = Hexpm.Billing.get(organization.name)

    if customer["quantity"] > user_count do
      if user = Users.public_get(username, [:emails]) do
        params = %{"role" => params["role"]}

        case Organizations.add_member(organization, user, params, audit: audit_data(conn)) do
          {:ok, organization_user} ->
            location = Routes.api_organization_user_url(conn, :show, name, user.username)

            conn
            |> api_cache(:private)
            |> put_resp_header("location", location)
            |> render(:show, user: user, role: organization_user.role)

          {:error, :organization_user} ->
            validation_failed(conn, "cannot add an organization as member to an organization")

          {:error, changeset} ->
            validation_failed(conn, changeset)
        end
      else
        validation_failed(conn, %{"name" => "unknown user"})
      end
    else
      validation_failed(conn, "not enough seats to add member")
    end
  end

  def update(conn, %{"organization" => name, "name" => username} = params) do
    organization = Organizations.get(name)

    if user = Users.public_get(username, [:emails]) do
      params = %{"role" => params["role"]}

      case Organizations.change_role(organization, user, params, audit: audit_data(conn)) do
        {:ok, organization_user} ->
          conn
          |> api_cache(:private)
          |> render(:show, user: user, role: organization_user.role)

        {:error, :last_admin} ->
          validation_failed(conn, "cannot demote last admin member")

        {:error, changeset} ->
          validation_failed(conn, changeset)
      end
    else
      not_found(conn)
    end
  end

  def delete(conn, %{"organization" => name, "name" => username}) do
    organization = Organizations.get(name)
    user = Users.public_get(username)

    case Organizations.remove_member(organization, user, audit: audit_data(conn)) do
      :ok ->
        conn
        |> api_cache(:private)
        |> send_resp(204, "")

      {:error, :last_member} ->
        validation_failed(conn, "cannot remove last member")
    end
  end
end
