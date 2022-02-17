defmodule HexpmWeb.API.OwnerController do
  use HexpmWeb, :controller

  plug :maybe_fetch_package

  plug :authorize,
       [domain: "api", resource: "read", fun: &organization_access/2]
       when action in [:index, :show]

  plug :authorize,
       [
         domain: "api",
         resource: "write",
         fun: [&package_owner/3, &organization_billing_active/3],
         opts: [owner_level: "full"]
       ]
       when action in [:create, :delete]

  def index(conn, _params) do
    if package = conn.assigns.package do
      owners = Owners.all(package, user: :emails)

      conn
      |> api_cache(:private)
      |> render(:index, owners: owners)
    else
      not_found(conn)
    end
  end

  def show(conn, %{"username" => name}) do
    package = conn.assigns.package
    name = URI.decode_www_form(name)
    user = Users.public_get(name, [:emails])

    if package && user do
      if owner = Owners.get(package, user) do
        conn
        |> api_cache(:private)
        |> render(:show, owner: owner)
      else
        not_found(conn)
      end
    else
      not_found(conn)
    end
  end

  def create(conn, %{"username" => name} = params) do
    if package = conn.assigns.package do
      name = URI.decode_www_form(name)
      new_owner = Users.public_get(name, [:emails])

      if new_owner do
        case Owners.add(package, new_owner, params, audit: audit_data(conn)) do
          {:ok, _owner} ->
            conn
            |> api_cache(:private)
            |> send_resp(204, "")

          {:error, :not_member} ->
            validation_failed(conn, %{
              "username" => "cannot add owner that is not a member of the organization"
            })

          {:error, :not_organization_transfer} ->
            validation_failed(conn, %{
              "username" =>
                "organization ownership can only be transferred, removing all existing owners"
            })

          {:error, :organization_level} ->
            validation_failed(conn, %{
              "level" => "ownership level is required to be \"full\" for organization ownership"
            })

          {:error, :organization_user_conflict} ->
            validation_failed(conn, %{
              "username" =>
                "cannot add organization as owner until user account and organization is merged, " <>
                  "please contact support@hex.pm to manually merge accounts"
            })

          {:error, changeset} ->
            validation_failed(conn, changeset)
        end
      else
        not_found(conn)
      end
    else
      not_found(conn)
    end
  end

  def delete(conn, %{"username" => name}) do
    if package = conn.assigns.package do
      name = URI.decode_www_form(name)
      remove_owner = Users.get(name)

      if remove_owner do
        case Owners.remove(package, remove_owner, audit: audit_data(conn)) do
          :ok ->
            conn
            |> api_cache(:private)
            |> send_resp(204, "")

          {:error, :not_owner} ->
            validation_failed(conn, %{"username" => "user is not an owner of package"})

          {:error, :last_owner} ->
            validation_failed(conn, %{"username" => "cannot remove last owner of package"})
        end
      else
        not_found(conn)
      end
    else
      not_found(conn)
    end
  end
end
