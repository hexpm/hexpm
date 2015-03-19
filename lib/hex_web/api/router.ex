defmodule HexWeb.API.Router do
  use Plug.Router
  import Plug.Conn
  import HexWeb.API.Util
  import HexWeb.Util, only: [api_url: 1, parse_integer: 2, task_start: 1]
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

    if package = Package.get(name) do
      with_authorized(conn, [], &Package.owner?(package, &1), fn _ ->
        case read_body(conn, HexWeb.request_read_opts) do
          {:ok, body, conn} ->
            handle_publish(conn, package, body)
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

  post "packages/:name/releases/:version/docs" do
    conn = HexWeb.Plug.read_body_finally(conn)

    if (package = Package.get(name)) && (release = Release.get(package, version)) do
      with_authorized(conn, [], &Package.owner?(package, &1), fn _ ->
        case read_body(conn, HexWeb.request_read_opts) do
          {:ok, body, conn} ->
            handle_docs(conn, release, body)
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

  defp handle_publish(conn, package, body) do
    case HexWeb.Tar.metadata(body) do
      {:ok, meta, checksum} ->
        app     = meta["app"]
        version = meta["version"]
        reqs    = meta["requirements"] || %{}

        if release = Release.get(package, version) do
          result = Release.update(release, app, reqs, checksum)
          if match?({:ok, _}, result), do: after_release(package, version, body)
          send_update_resp(conn, result, :public)
        else
          result = Release.create(package, version, app, reqs, checksum)
          if match?({:ok, _}, result), do: after_release(package, version, body)
          send_creation_resp(conn, result, :public, api_url(["packages", package.name, "releases", version]))
        end

      {:error, errors} ->
        send_validation_failed(conn, %{tar: errors})
    end
  end

  defp handle_docs(conn, release, body) do
    case :erl_tar.extract({:binary, body}, [:memory, :compressed]) do
      {:ok, files} ->
        files = Enum.map(files, fn {path, data} -> {List.to_string(path), data} end)

        if check_version_dirs?(files) do
          package  = release.package
          name     = package.name
          version  = release.version

          task_start(fn ->
            store = Application.get_env(:hex_web, :store)

            # Delete old files
            paths = store.list_docs_pages(name)
            Enum.each(paths, fn path ->
              first = Path.relative_to(path, name)|> Path.split |> hd
              cond do
                # Current (/ecto/0.8.1/...)
                first == version ->
                  store.delete_docs_page(path)
                # Top-level docs, don't match version directories (/ecto/...)
                Version.parse(first) == :error ->
                  store.delete_docs_page(path)
                true ->
                  :ok
              end
            end)

            # Put tarball
            store.put_docs("#{name}-#{version}.tar.gz", body)

            # Upload new files
            Enum.each(files, fn {path, data} ->
              store.put_docs_page(Path.join([name, version, path]), data)
              store.put_docs_page(Path.join(name, path), data)
            end)

            # Set docs flag on release
            %{release | has_docs: true}
            |> HexWeb.Repo.update
          end)

          location = api_url(["packages", name, "releases", version, "docs"])

          conn
          |> put_resp_header("location", location)
          |> cache(:public)
          |> send_resp(201, "")
        else
          send_validation_failed(conn, %{tar: "directory name not allowed to match a semver version"})
        end

      {:error, reason} ->
        send_validation_failed(conn, %{tar: inspect reason})
    end
  end

  defp check_version_dirs?(files) do
    Enum.all?(files, fn {path, _data} ->
      first = Path.split(path) |> hd
      Version.parse(first) == :error
    end)
  end

  defp after_release(package, version, body) do
    task_start(fn ->
      store = Application.get_env(:hex_web, :store)
      store.put_release("#{package.name}-#{version}.tar", body)
      HexWeb.RegistryBuilder.rebuild
    end)
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

    post "users" do
      username = conn.params["username"]
      email    = conn.params["email"]
      password = conn.params["password"]

      # Unconfirmed users can be recreated
      if (user = User.get(username: username)) && not user.confirmed do
        User.delete(user)
      end

      result = User.create(username, email, password)
      send_creation_resp(conn, result, :public, api_url(["users", username]))
    end

    get "users/:name" do
      with_authorized(conn, [], &(&1.username == name), fn user ->
        when_stale(conn, user, &send_okay(&1, user, :public))
      end)
    end

    post "users/:name/reset" do
      if (user = User.get(username: name) || User.get(email: name)) do
        User.initiate_password_reset(user)

        conn
        |> cache(:private)
        |> send_resp(204, "")
      else
        raise NotFound
      end
    end

    get "packages" do
      page = parse_integer(conn.params["page"], 1)
      packages = Package.all(page, 100, conn.params["search"])
      # No last-modified header for paginated results
      when_stale(conn, packages, [modified: false], &send_okay(&1, packages, :public))
    end

    get "packages/:name" do
      if package = Package.get(name) do
        when_stale(conn, package, fn conn ->
          downloads = HexWeb.Stats.PackageDownload.package(package)
          releases = Release.all(package)
          package = %{package | releases: releases, downloads: downloads}

          send_okay(conn, package, :public)
        end)
      else
        raise NotFound
      end
    end

    put "packages/:name" do
      if package = Package.get(name) do
        with_authorized(conn, [], &Package.owner?(package, &1), fn _ ->
          result = Package.update(package, conn.params["meta"])
          send_update_resp(conn, result, :public)
        end)
      else
        with_authorized(conn, [], fn user ->
          result = Package.create(name, user, conn.params["meta"])
          send_creation_resp(conn, result, :public, api_url(["packages", name]))
        end)
      end
    end

    delete "packages/:name/releases/:version" do
      if (package = Package.get(name)) && (release = Release.get(package, version)) do
        with_authorized(conn, [], &Package.owner?(package, &1), fn _ ->
          result = Release.delete(release)

          if result == :ok do
            task_start(fn ->
              store = Application.get_env(:hex_web, :store)

              # Delete release tarball
              store.delete_release("#{name}-#{version}.tar")

              # Delete relevant documentation (if it exists)
              if release.has_docs do
                paths = store.list_docs_pages(Path.join(name, version))
                store.delete_docs("#{name}-#{version}.tar.gz")
                Enum.each(paths, fn path ->
                  store.delete_docs_page(path)
                end)
              end

              HexWeb.RegistryBuilder.rebuild
            end)
          end

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

          task_start(fn ->
            store = Application.get_env(:hex_web, :store)
            paths = store.list_docs_pages(Path.join(name, version))
            store.delete_docs("#{name}-#{version}.tar.gz")

            Enum.each(paths, fn path ->
              store.delete_docs_page(path)
            end)

            %{release | has_docs: false}
            |> HexWeb.Repo.update
          end)

          conn
          |> cache(:private)
          |> send_resp(204, "")
        end)
      else
        raise NotFound
      end
    end

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
        name = conn.params["name"]
        result = Key.create(name, user)
        send_creation_resp(conn, result, :private, api_url(["keys", name]))
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
