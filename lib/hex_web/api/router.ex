defmodule HexWeb.API.Router do
  use Plug.Router
  import Plug.Conn
  import HexWeb.Plug
  import HexWeb.API.Util
  import HexWeb.Util, only: [api_url: 1, parse_integer: 2]
  alias HexWeb.Plug.NotFound
  alias HexWeb.Plugs
  alias HexWeb.User
  alias HexWeb.Package
  alias HexWeb.Release
  alias HexWeb.API.Key


  plug Plugs.Format
  plug :match
  plug :dispatch

  post "packages/:name/releases" do
    if package = Package.get(name) do
      user_id = package.owner_id

      with_authorized(_user, id: user_id) do
        { body, conn } = read_body!(conn, 10_000_000)

        case HexWeb.Tar.metadata(body) do
          { :ok, meta } ->
            version = meta["version"]
            reqs    = meta["requirements"] || []

            if release = Release.get(package, version) do
              result = Release.update(release, reqs)
              if match?({ :ok, _ }, result), do: after_release(name, version, body)
              send_update_resp(conn, result, :public)
            else
              result = Release.create(package, version, reqs)
              if match?({ :ok, _ }, result), do: after_release(name, version, body)
              send_creation_resp(conn, result, :public, api_url(["packages", name, "releases", version]))
            end

          { :error, errors } ->
            send_validation_failed(conn, errors)
        end
      end
    else
      send_resp(conn, 404, "")
    end
  end

  defp after_release(name, version, body) do
    HexWeb.Config.store.put_tar("#{name}-#{version}.tar", body)
    HexWeb.RegistryBuilder.async_rebuild
  end

  match _ do
    HexWeb.API.Router.Parsed.call(conn, [])
  end

  defmodule Parsed do
    use Plug.Router

    plug Plug.Parsers, parsers: [HexWeb.Parsers.Json, HexWeb.Parsers.Elixir]
    plug :match
    plug :dispatch

    post "users" do
      username = conn.params["username"]
      result = User.create(username, conn.params["email"], conn.params["password"])
      send_creation_resp(conn, result, :public, api_url(["users", username]))
    end

    get "users/:name" do
      if user = User.get(name) do
        when_stale user, do: conn |> cache(:public) |> send_render(200, user)
      else
        raise NotFound
      end
    end

    patch "users/:name" do
      name = String.downcase(name)
      with_authorized_basic(user, username: name) do
        result = User.update(user, conn.params["email"], conn.params["password"])
        send_update_resp(conn, result, :public)
      end
    end

    get "packages" do
      page = parse_integer(conn.params["page"], 1)
      packages = Package.all(page, 100, conn.params["search"])
      when_stale packages, do: conn |> cache(:public) |> send_render(200, packages)
    end

    get "packages/:name" do
      if package = Package.get(name) do
        when_stale package, do: conn |> cache(:public) |> send_render(200, package)
      else
        raise NotFound
      end
    end

    put "packages/:name" do
      if package = Package.get(name) do
        user_id = package.owner_id
        with_authorized(_user, id: user_id) do
          result = Package.update(package, conn.params["meta"])
          send_update_resp(conn, result, :public)
        end
      else
        with_authorized(user) do
          result = Package.create(name, user, conn.params["meta"])
          send_creation_resp(conn, result, :public, api_url(["packages", name]))
        end
      end
    end

    delete "packages/:name/releases/:version" do
      if (package = Package.get(name)) && (release = Release.get(package, version)) do
        user_id = package.owner_id

        with_authorized(_user, id: user_id) do
          result = Release.delete(release)

          if result == :ok do
            HexWeb.Config.store.delete_tar("#{name}-#{version}.tar")
            HexWeb.RegistryBuilder.async_rebuild
          end

          send_delete_resp(conn, result, :public)
        end
      else
        raise NotFound
      end
    end

    get "packages/:name/releases/:version" do
      if (package = Package.get(name)) && (release = Release.get(package, version)) do
        when_stale release, do: conn |> cache(:public) |> send_render(200, release)
      else
        raise NotFound
      end
    end

    get "keys" do
      with_authorized_basic(user) do
        keys = Key.all(user)
        when_stale keys, do: conn |> cache(:private) |> send_render(200, keys)
      end
    end

    get "keys/:name" do
      with_authorized_basic(user) do
        if key = Key.get(name, user) do
          when_stale key, do: conn |> cache(:private) |> send_render(200, key)
        else
          raise NotFound
        end
      end
    end

    post "keys" do
      with_authorized_basic(user) do
        name = conn.params["name"]
        result = Key.create(name, user)
        send_creation_resp(conn, result, :private, api_url(["keys", name]))
      end
    end

    delete "keys/:name" do
      with_authorized_basic(user) do
        if key = Key.get(name, user) do
          result = Key.delete(key)
          send_delete_resp(conn, result, :private)
        else
          raise NotFound
        end
      end
    end

    match _ do
      _conn = conn
      raise NotFound
    end
  end
end
