defmodule HexWeb.Router.API do
  use Plug.Router
  import Plug.Connection
  import HexWeb.Router.Util
  import HexWeb.Util, only: [url: 1  ]
  alias HexWeb.Plugs
  alias HexWeb.User
  alias HexWeb.Package
  alias HexWeb.Release
  alias HexWeb.RegistryBuilder


  plug Plug.Parsers, parsers: [HexWeb.Parsers.Json, HexWeb.Parsers.Elixir]
  plug Plugs.Accept, vendor: "hex", allow: [{"application","json"}, "json", "elixir"]
  plug Plugs.Version
  plug :match
  plug :dispatch


  post "users" do
    username = conn.params["username"]
    User.create(username, conn.params["email"], conn.params["password"])
    |> send_creation_resp(conn, url(["users", username]))
  end

  get "users/:name" do
    if user = User.get(name) do
      send_render(conn, 200, user)
    else
      send_resp(conn, 404, "")
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
    with_authorized user do
      if package = Package.get(name) do
        package.meta(conn.params["meta"])
        |> Package.update
        |> send_update_resp(conn)
      else
        Package.create(name, user, conn.params["meta"])
        |> send_creation_resp(conn, url(["packages", name]))
      end
    end
  end

  post "packages/:name/releases" do
    with_authorized do
      if package = Package.get(name) do
        version = conn.params["version"]
        result =
          Release.create(package, version, conn.params["git_url"],
                         conn.params["git_ref"], conn.params["requirements"])
          |> send_creation_resp(conn, url(["packages", name, "releases", version]))

        RegistryBuilder.rebuild
        result
      else
        send_resp(conn, 404, "")
      end
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
