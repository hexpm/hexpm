defmodule HexWeb.API.OwnerController do
  use HexWeb.Web, :controller

  def index(conn, %{"name" => name}) do
    if package = HexWeb.Repo.get_by(Package, name: name) do
      authorized(conn, [], &package_owner?(package, &1), fn _ ->
        owners =  Package.owners(package) |> HexWeb.Repo.all
        conn
        |> api_cache(:private)
        |> render(:index, owners: owners)
      end)
    else
      not_found(conn)
    end
  end

  def show(conn, %{"name" => name, "email" => email}) do
    email = URI.decode_www_form(email)

    if (package = HexWeb.Repo.get_by(Package, name: name)) && (owner = User.get(email: email)) do
      authorized(conn, [], &package_owner?(package, &1), fn _ ->
        if package_owner?(package, owner) do
          conn
          |> api_cache(:private)
          |> send_resp(204, "")
        end
      end)
    end || not_found(conn)
  end

  def create(conn, %{"name" => name, "email" => email}) do
    email = URI.decode_www_form(email)

    if (package = HexWeb.Repo.get_by(Package, name: name)) && (user = User.get(email: email)) do
      authorized(conn, [], &package_owner?(package, &1), fn _ ->
        Package.create_owner(package, user) |> HexWeb.Repo.insert!

        conn
        |> api_cache(:private)
        |> send_resp(204, "")
      end)
    else
      not_found(conn)
    end
  end

  def delete(conn, %{"name" => name, "email" => email}) do
    email = URI.decode_www_form(email)

    if (package = HexWeb.Repo.get_by(Package, name: name)) && (owner = User.get(email: email)) do
      authorized(conn, [], &package_owner?(package, &1), fn _ ->
        if HexWeb.Repo.one!(Package.is_single_owner(package)) do
          conn
          |> api_cache(:private)
          |> send_resp(403, "")
        else
          Package.owner(package, owner)
          |> HexWeb.Repo.delete_all

          conn
          |> api_cache(:private)
          |> send_resp(204, "")
        end
      end)
    else
      not_found(conn)
    end
  end
end
