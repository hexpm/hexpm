defmodule HexWeb.API.OwnerController do
  use HexWeb.Web, :controller

  plug :fetch_package
  # NOTE: Disabled while waiting for privacy policy grace period
  # plug :authorize, fun: &package_owner?/2 when not action in [:index, :show]
  plug :authorize, fun: &package_owner?/2

  def index(conn, _params) do
    owners =
      conn.assigns.package
      |> Owners.all
      |> Users.with_emails

    conn
    |> api_cache(:private)
    |> render(:index, owners: owners)
  end

  def show(conn, %{"email" => email}) do
    email = URI.decode_www_form(email)
    owner = Users.get(email)

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
    new_owner = Users.get(email)
    package = conn.assigns.package

    if new_owner do
      case Owners.add(package, new_owner, audit: audit_data(conn)) do
        :ok ->
          conn
          |> api_cache(:private)
          |> send_resp(204, "")
        {:error, changeset} ->
          validation_failed(conn, changeset)
      end
    else
      not_found(conn)
    end
  end

  def delete(conn, %{"email" => email}) do
    email = URI.decode_www_form(email)
    remove_owner = Users.get(email)
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
