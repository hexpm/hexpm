defmodule Hexpm.Web.API.OwnerController do
  use Hexpm.Web, :controller

  plug :maybe_fetch_package
  plug :authorize, [domain: "api", fun: &repository_access/2] when action in [:index, :show]
  plug :authorize, [domain: "api", fun: &maybe_package_owner/2] when action in [:create, :delete]
  plug :authorize, [domain: "api", fun: &repository_billing_active/2] when action in [:create, :delete]

  def index(conn, _params) do
    if package = conn.assigns.package do
      owners = Owners.all(package, [:emails])

      conn
      |> api_cache(:private)
      |> render(:index, owners: owners)
    else
      not_found(conn)
    end
  end

  def show(conn, %{"email" => email}) do
    if package = conn.assigns.package do
      email = URI.decode_www_form(email)
      owner = Users.get(email)

      if package_owner(package, owner) == :ok do
        conn
        |> api_cache(:private)
        |> send_resp(204, "")
      end
    end || not_found(conn)
  end

  def create(conn, %{"email" => email}) do
    if package = conn.assigns.package do
      email = URI.decode_www_form(email)
      new_owner = Users.get(email)

      if new_owner do
        case Owners.add(package, new_owner, audit: audit_data(conn)) do
          :ok ->
            conn
            |> api_cache(:private)
            |> send_resp(204, "")

          {:error, :not_member} ->
            validation_failed(conn, %{
              "email" => "cannot add owner that is not a member of the repository"
            })

          {:error, changeset} ->
            validation_failed(conn, changeset)
        end
      end
    end || not_found(conn)
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
      end
    end || not_found(conn)
  end
end
