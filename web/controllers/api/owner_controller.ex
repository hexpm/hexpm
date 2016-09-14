defmodule HexWeb.API.OwnerController do
  use HexWeb.Web, :controller

  plug :fetch_package
  plug :authorize, fun: &package_owner?/2

  def index(conn, _params) do
    owners = Owners.all(conn.assigns.package)

    conn
    |> api_cache(:private)
    |> render(:index, owners: owners)
  end

  def show(conn, %{"email" => email}) do
    email = URI.decode_www_form(email)
    owner = Owners.get(email)

    if package_owner?(conn.assigns.package, owner) do
      conn
      |> api_cache(:private)
      |> send_resp(204, "")
    else
      not_found(conn)
    end
  end

  def create(conn, %{"email" => email}) do
    email = URI.decode_www_form(email)
    new_owner = Owners.get(email)
    package = conn.assigns.package

    case Owners.add(package, new_owner, audit: audit_data(conn)) do
      :ok ->
        conn
        |> api_cache(:private)
        |> send_resp(204, "")
      {:error, changeset} ->
        validation_failed(conn, changeset)
    end
  end

  def delete(conn, %{"email" => email}) do
    email = URI.decode_www_form(email)
    remove_owner = Owners.get(email)
    package = conn.assigns.package

    case Owners.remove(package, remove_owner, audit: audit_data(conn)) do
      :ok ->
        conn
        |> api_cache(:private)
        |> send_resp(204, "")
      {:error, :last_owner} ->
        conn
        |> api_cache(:private)
        |> send_resp(403, "")
    end
  end
end
