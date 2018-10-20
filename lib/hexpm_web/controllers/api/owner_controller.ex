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
         fun: [&maybe_full_package_owner/2, &organization_billing_active/2]
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

  def show(conn, %{"email" => email}) do
    package = conn.assigns.package
    email = URI.decode_www_form(email)
    user = Users.public_get(email, [:emails])

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

  def create(conn, %{"email" => email} = params) do
    if package = conn.assigns.package do
      email = URI.decode_www_form(email)
      new_owner = Users.public_get(email, [:emails])

      if new_owner do
        case Owners.add(package, new_owner, params, audit: audit_data(conn)) do
          {:ok, _owner} ->
            conn
            |> api_cache(:private)
            |> send_resp(204, "")

          {:error, :not_member} ->
            errors = %{"email" => "cannot add owner that is not a member of the organization"}
            validation_failed(conn, errors)

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

  def delete(conn, %{"email" => email}) do
    if package = conn.assigns.package do
      email = URI.decode_www_form(email)
      remove_owner = Users.get(email)

      if remove_owner do
        case Owners.remove(package, remove_owner, audit: audit_data(conn)) do
          :ok ->
            conn
            |> api_cache(:private)
            |> send_resp(204, "")

          {:error, :not_owner} ->
            validation_failed(conn, %{"email" => "user is not an owner of package"})

          {:error, :last_owner} ->
            validation_failed(conn, %{"email" => "cannot remove last owner of package"})
        end
      else
        not_found(conn)
      end
    else
      not_found(conn)
    end
  end
end
