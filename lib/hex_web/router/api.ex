defmodule HexWeb.Router.API do
  use Plug.Router
  import Plug.Connection
  import HexWeb.Router.Util
  import HexWeb.Util, only: [api_url: 1]
  alias HexWeb.Plugs
  alias HexWeb.User
  alias HexWeb.Package
  alias HexWeb.Release


  plug Plug.Parsers, parsers: [HexWeb.Parsers.Json, HexWeb.Parsers.Elixir]
  plug Plugs.Accept, vendor: "hex", allow: [{"application","json"}, "json", "elixir"]
  plug Plugs.Version
  plug :match
  plug :dispatch


  post "users" do
    username = conn.params["username"]
    User.create(username, conn.params["email"], conn.params["password"])
    |> send_creation_resp(conn, api_url(["users", username]))
  end

  get "users/:name" do
    if user = User.get(name) do
      send_render(conn, 200, user)
    else
      send_resp(conn, 404, "")
    end
  end

  patch "users/:name" do
    name = String.downcase(name)
    with_authorized_as(user, username: name) do
      User.update(user, conn.params["email"], conn.params["password"])
      |> send_update_resp(conn)
    end
  end

  get "packages" do
    page = parse_integer(conn.params["page"], 1)
    packages = Package.all(page, 100, conn.params["search"])
    send_render(conn, 200, packages)
  end

  get "packages/:name" do
    if package = Package.get(name) do
      send_render(conn, 200, package)
    else
      send_resp(conn, 404, "")
    end
  end

  put "packages/:name" do
    if package = Package.get(name) do
      user_id = package.owner_id
      with_authorized_as(id: user_id) do
        Package.update(package, conn.params["meta"])
        |> send_update_resp(conn)
      end
    else
      with_authorized(user) do
        Package.create(name, user, conn.params["meta"])
        |> send_creation_resp(conn, api_url(["packages", name]))
      end
    end
  end

  delete "packages/:name/releases/:version" do
    if (package = Package.get(name)) && (release = Release.get(package, version)) do
      user_id = package.owner_id

      with_authorized_as(id: user_id) do
        result = Release.delete(release)

        if result == :ok do
          HexWeb.Config.store.delete_tar("#{name}-#{version}.tar")
          HexWeb.RegistryBuilder.rebuild
        end

        send_delete_resp(result, conn)
      end
    else
      send_resp(conn, 404, "")
    end
  end

  get "packages/:name/releases/:version" do
    if (package = Package.get(name)) && (release = Release.get(package, version)) do
      send_render(conn, 200, release)
    else
      send_resp(conn, 404, "")
    end
  end

  match _ do
    send_resp(conn, 404, "")
  end
end
