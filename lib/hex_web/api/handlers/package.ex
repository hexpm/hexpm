defmodule HexWeb.API.Handlers.Package do
  import HexWeb.API.Util
  import HexWeb.Util, only: [api_url: 1, task: 3]
  alias HexWeb.Package
  alias HexWeb.Release

  def publish(conn, package, user, body) do
    case HexWeb.Tar.metadata(body) do
      {:ok, meta, checksum} ->
        if package do
          create_release(conn, package, user, checksum, meta, body)
        else
          package_params = %{"name" => meta["name"], "meta" => meta}
          case create_package(conn, package_params) do
            {:ok, package} ->
              create_release(conn, package, user, checksum, meta, body)
            {:error, errors} ->
              send_validation_failed(conn, %{package: errors})
          end
        end

      {:error, errors} ->
        send_validation_failed(conn, %{tar: errors})
    end
  end

  defp create_release(conn, package, user, checksum, meta, body) do
    version = meta["version"]
    release_params = %{"app" => meta["app"], "version" => version,
                       "requirements" => meta["requirements"], "meta" => meta}

    if release = Release.get(package, version) do
      result = Release.update(release, release_params, checksum)
      if match?({:ok, _}, result), do: after_release(package, version, user, body)
      send_update_resp(conn, result, :public)
    else
      result = Release.create(package, release_params, checksum)
      if match?({:ok, _}, result), do: after_release(package, version, user, body)
      send_creation_resp(conn, result, :public, api_url(["packages", package.name, "releases", version]))
    end
  end

  defp create_package(conn, params) do
    name = params["name"]

    if package = Package.get(name) do
      with_authorized(conn, [], &Package.owner?(package, &1), fn _ ->
        Package.update(package, params)
      end)
    else
      with_authorized(conn, [], fn user ->
        Package.create(user, params)
      end)
    end
  end

  defp after_release(package, version, user, body) do
    task    = fn -> job(package, version, body) end
    success = fn -> success(package, version, user) end
    failure = fn -> failure(package, version, user) end
    task(task, success, failure)
  end

  defp job(package, version, body) do
    store = Application.get_env(:hex_web, :store)
    store.put_release("#{package.name}-#{version}.tar", body)
    HexWeb.RegistryBuilder.rebuild
  end

  defp success(package, version, user) do
    email = Application.get_env(:hex_web, :email)
    body  = HexWeb.Email.Templates.render(:publish_success,
                                            package: package.name,
                                            version: version,
                                            docs: false)
    title = "Hex.pm - #{package.name} v#{version} has been published"
    email.send(user.email, title, body)
  end

  defp failure(package, version, user) do
    # TODO: Revert database changes
    email = Application.get_env(:hex_web, :email)
    body  = HexWeb.Email.Templates.render(:publish_fail,
                                            package: package.name,
                                            version: version,
                                            docs: false)
    title = "Hex.pm - #{package.name} v#{version} failed to publish successfully"
    email.send(user.email, title, body)
  end

  def revert(name, release) do
    task = fn ->
      version = to_string(release.version)
      store   = Application.get_env(:hex_web, :store)

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
    end

    # TODO: Send mails
    task(task, fn -> end, fn -> end)
  end
end
