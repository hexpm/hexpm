defmodule HexWeb.API.OwnerController do
  use HexWeb.Web, :controller

  def index(conn, %{"name" => name}) do
    if package = Package.get(name) do
      authorized(conn, [], &Package.owner?(package, &1), fn _ ->
        conn
        |> api_cache(:private)
        |> render(:index, owners: Package.owners(package))
      end)
    else
      not_found(conn)
    end
  end

  def show(conn, %{"name" => name, "email" => email}) do
    email = URI.decode_www_form(email)

    if (package = Package.get(name)) && (owner = User.get(email: email)) do
      authorized(conn, [], &Package.owner?(package, &1), fn _ ->
        if Package.owner?(package, owner) do
          conn
          |> api_cache(:private)
          |> send_resp(204, "")
        end
      end)
    end || not_found(conn)
  end

  def create(conn, %{"name" => name, "email" => email}) do
    email = URI.decode_www_form(email)

    if (package = Package.get(name)) && (owner = User.get(email: email)) do
      authorized(conn, [], &Package.owner?(package, &1), fn _ ->
        Package.add_owner(package, owner)

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

    if (package = Package.get(name)) && (owner = User.get(email: email)) do
      authorized(conn, [], &Package.owner?(package, &1), fn _ ->
        if Package.last_owner?(package) do
          conn
          |> api_cache(:private)
          |> send_resp(403, "")
        else
          Package.delete_owner(package, owner)

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
