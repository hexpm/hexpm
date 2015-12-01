defmodule HexWeb.API.Router do
  use Plug.Router
  import Plug.Conn
  import HexWeb.API.Util
  import HexWeb.Util, only: [api_url: 1]
  alias HexWeb.Util
  alias HexWeb.Plug.NotFound
  alias HexWeb.Plug.RequestTimeout
  alias HexWeb.Plug.RequestTooLarge
  alias HexWeb.Plugs
  alias HexWeb.User
  alias HexWeb.Package
  alias HexWeb.Release
  alias HexWeb.API.Key

  plug Plugs.Format
  plug HexWeb.API.RateLimit.Plug
  plug :match
  plug :dispatch

  post "packages/:name/releases" do
    conn = HexWeb.Plug.read_body_finally(conn)

    auth =
      if package = Package.get(name) do
        &Package.owner?(package, &1)
      else
        fn _ -> true end
      end

    with_authorized(conn, [], auth, fn user ->
      case read_body(conn, HexWeb.request_read_opts) do
        {:ok, body, conn} ->
          HexWeb.API.Handlers.Package.publish(conn, package, user, body)
        {:error, :timeout} ->
          raise RequestTimeout
        {:error, _} ->
          send_resp(conn, 400, "")
        {:more, _, _} ->
          raise RequestTooLarge
      end
    end)
  end

  post "packages/:name/releases/:version/docs" do
    conn = HexWeb.Plug.read_body_finally(conn)

    if (package = Package.get(name)) && (release = Release.get(package, version)) do
      with_authorized(conn, [], &Package.owner?(package, &1), fn user ->
        case read_body(conn, HexWeb.request_read_opts) do
          {:ok, body, conn} ->
            HexWeb.API.Handlers.Docs.publish(conn, release, user, body)
          {:error, :timeout} ->
            raise RequestTimeout
          {:more, _, _} ->
            raise RequestTooLarge
        end
      end)
    else
      raise NotFound
    end
  end

  match _ do
    HexWeb.API.Router.Parsed.call(conn, [])
  end

  defmodule Parsed do
    use Plug.Router

    plug Plug.Parsers, parsers: [:json, HexWeb.Parsers.HexVendor],
                       json_decoder: Poison
    plug :match
    plug :dispatch

    # Users

    post "users" do
      # Unconfirmed users can be recreated
      if (user = User.get(username: conn.params["username"])) && not user.confirmed do
        User.delete(user)
      end

      result = User.create(conn.params)
      send_creation_resp(conn, result, :public, api_url(["users", conn.params["username"]]))
    end

    get "users/:name" do
      with_authorized(conn, [], &(&1.username == name), fn user ->
        user_with_packages = HexWeb.Repo.preload(user, :owned_packages)
        when_stale(conn, user_with_packages, &send_okay(&1, user_with_packages, :public))
      end)
    end

    post "users/:name/reset" do
      if (user = User.get(username: name) || User.get(email: name)) do
        User.password_reset(user)

        conn
        |> cache(:private)
        |> send_resp(204, "")
      else
        raise NotFound
      end
    end

    # Packages

    get "packages" do
      page     = Util.safe_int(conn.params["page"])
      search   = conn.params["search"] |> Util.safe_search
      sort     = Util.safe_to_atom(conn.params["sort"] || "name", ~w(name downloads inserted_at updated_at))
      packages = Package.all(page, 100, search, sort)

      # No last-modified header for paginated results
      when_stale(conn, packages, [modified: false], &send_okay(&1, packages, :public))
    end

    get "packages/:name" do
      if package = Package.get(name) do
        when_stale(conn, package, fn conn ->
          package = HexWeb.Repo.preload(package, :downloads)
          releases = Release.all(package)
          package = %{package | releases: releases}

          send_okay(conn, package, :public)
        end)
      else
        raise NotFound
      end
    end

    delete "packages/:name/releases/:version" do
      if (package = Package.get(name)) && (release = Release.get(package, version)) do
        with_authorized(conn, [], &Package.owner?(package, &1), fn _ ->
          result = Release.delete(release)

          if result == :ok do
            HexWeb.API.Handlers.Package.revert(name, release)
          end

          # TODO: Remove package from database if this was the only release

          send_delete_resp(conn, result, :public)
        end)
      else
        raise NotFound
      end
    end

    get "packages/:name/releases/:version" do
      if (package = Package.get(name)) && (release = Release.get(package, version)) do
        when_stale(conn, release, fn conn ->
          downloads = HexWeb.Stats.ReleaseDownload.release(release)
          release = %{release | downloads: downloads}

          send_okay(conn, release, :public)
        end)
      else
        raise NotFound
      end
    end

    # Release Docs

    get "packages/:name/releases/:version/docs" do
      if (package = Package.get(name)) && Release.get(package, version) do
        store = Application.get_env(:hex_web, :store)
        store.send_docs(conn, "#{name}-#{version}.tar.gz")
      else
        raise NotFound
      end
    end

    delete "packages/:name/releases/:version/docs" do
      if (package = Package.get(name)) && (release = Release.get(package, version)) do
        with_authorized(conn, [], &Package.owner?(package, &1), fn _ ->

          HexWeb.API.Handlers.Docs.revert(name, release)

          conn
          |> cache(:private)
          |> send_resp(204, "")
        end)
      else
        raise NotFound
      end
    end

    # Package Owners

    get "packages/:name/owners" do
      if package = Package.get(name) do
        with_authorized(conn, [], &Package.owner?(package, &1), fn _ ->
          send_okay(conn, Package.owners(package), :public)
        end)
      else
        raise NotFound
      end
    end

    get "packages/:name/owners/:email" do
      email = URI.decode_www_form(email)

      if (package = Package.get(name)) && (owner = User.get(email: email)) do
        with_authorized(conn, [], &Package.owner?(package, &1), fn _ ->
          if Package.owner?(package, owner) do
            conn
            |> cache(:private)
            |> send_resp(204, "")
          else
            raise NotFound
          end
        end)
      else
        raise NotFound
      end
    end

    put "packages/:name/owners/:email" do
      email = URI.decode_www_form(email)

      if (package = Package.get(name)) && (owner = User.get(email: email)) do
        with_authorized(conn, [], &Package.owner?(package, &1), fn _ ->
          Package.add_owner(package, owner)

          conn
          |> cache(:private)
          |> send_resp(204, "")
        end)
      else
        raise NotFound
      end
    end

    delete "packages/:name/owners/:email" do
      email = URI.decode_www_form(email)

      if (package = Package.get(name)) && (owner = User.get(email: email)) do
        with_authorized(conn, [], &Package.owner?(package, &1), fn _ ->
          Package.delete_owner(package, owner)

          conn
          |> cache(:private)
          |> send_resp(204, "")
        end)
      else
        raise NotFound
      end
    end

    # Keys

    get "keys" do
      with_authorized(conn, [], fn user ->
        keys = Key.all(user)
        when_stale(conn, keys, &(&1 |> cache(:private) |> send_render(200, keys)))
      end)
    end

    get "keys/:name" do
      with_authorized(conn, [], fn user ->
        if key = Key.get(name, user) do
          when_stale(conn, key, &(&1 |> cache(:private) |> send_render(200, key)))
        else
          raise NotFound
        end
      end)
    end

    post "keys" do
      auth_opts = [only_basic: true, allow_unconfirmed: true]
      with_authorized(conn, auth_opts, fn user ->
        result = Key.create(user, conn.params)
        send_creation_resp(conn, result, :private, api_url(["keys", conn.params["name"]]))
      end)
    end

    delete "keys/:name" do
      with_authorized(conn, [], fn user ->
        if key = Key.get(name, user) do
          result = Key.delete(key)
          send_delete_resp(conn, result, :private)
        else
          raise NotFound
        end
      end)
    end

    match _ do
      _conn = conn
      raise NotFound
    end
  end
end
