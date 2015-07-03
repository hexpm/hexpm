defmodule HexWeb.API.Handlers.Package do
  import HexWeb.API.Util
  import HexWeb.Util, only: [api_url: 1, task_start: 1]
  alias HexWeb.Package
  alias HexWeb.Release

  def handle_publish(conn, package, body) do
    case HexWeb.Tar.metadata(body) do
      {:ok, meta, checksum} ->
        if package do
          create_release(conn, package, checksum, meta, body)
        else
          package_params = %{"name" => meta["name"], "meta" => meta}
          case create_package(conn, package_params) do
            {:ok, package} ->
              create_release(conn, package, checksum, meta, body)
            {:error, errors} ->
              send_validation_failed(conn, %{package: errors})
          end
        end

      {:error, errors} ->
        send_validation_failed(conn, %{tar: errors})
    end
  end

  defp create_release(conn, package, checksum, meta, body) do
    version = meta["version"]
    release_params = %{"app" => meta["app"], "version" => version,
                       "requirements" => meta["requirements"], "meta" => meta}

    if release = Release.get(package, version) do
      result = Release.update(release, release_params, checksum)
      if match?({:ok, _}, result), do: after_release(package, version, body)
      send_update_resp(conn, result, :public)
    else
      result = Release.create(package, release_params, checksum)
      if match?({:ok, _}, result), do: after_release(package, version, body)
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

  defp after_release(package, version, body) do
    task_start(fn ->
      store = Application.get_env(:hex_web, :store)
      store.put_release("#{package.name}-#{version}.tar", body)
      HexWeb.RegistryBuilder.rebuild
    end)
  end
end
