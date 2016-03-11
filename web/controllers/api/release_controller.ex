defmodule HexWeb.API.ReleaseController do
  use HexWeb.Web, :controller

  plug :fetch_release when action != :create
  plug :authorize, [fun: &package_owner?/2] when action == :delete

  def create(conn, %{"name" => name, "body" => body}) do
    auth =
      if package = HexWeb.Repo.get_by(Package, name: name) do
        &package_owner?(package, &1)
      else
        fn _ -> true end
      end

    conn = authorized(conn, [], auth)

    if conn.halted do
      conn
    else
      handle_tarball(conn, package, conn.assigns.user, body)
    end
  end

  def show(conn, _params) do
    release = conn.assigns.release

    release =
      HexWeb.Repo.preload(release,
        requirements: Release.requirements(release),
        downloads: ReleaseDownload.release(release))

    when_stale(conn, release, fn conn ->
      conn
      |> api_cache(:public)
      |> render(:show, release: release)
    end)
  end

  def delete(conn, _params) do
    result =
      HexWeb.Repo.transaction(fn ->
        case Release.delete(conn.assigns.release) |> HexWeb.Repo.delete do
          {:ok, release} ->
            audit(conn, "release.revert", {conn.assigns.package, release})
            release
          {:error, changeset} ->
            HexWeb.Repo.rollback(changeset)
        end
      end)

    case result do
      {:ok, release} ->
        # TODO: Remove package from database if this was the only release
        revert(release)

        conn
        |> api_cache(:private)
        |> send_resp(204, "")
      {:error, changeset} ->
        validation_failed(conn, changeset)
    end
  end

  defp handle_tarball(conn, package, user, body) do
    # TODO: with special form
    # TODO: Repo.transaction
    case HexWeb.Tar.metadata(body) do
      {:ok, meta, checksum} ->
        package_params = %{"name" => meta["name"], "meta" => meta}
        case create_package(user, package, package_params) do
          {:ok, package} ->
            create_release(conn, package, user, checksum, meta, body)
          {:error, changeset} ->
            validation_failed(conn, changeset)
        end

      {:error, errors} ->
        validation_failed(conn, %{tar: errors})
    end
  end

  defp create_package(user, package, params) do
    name = params["name"]
    package = package || HexWeb.Repo.get_by(Package, name: name)

    if package do
      Package.update(package, params)
      |> HexWeb.Repo.update
    else
      Package.create(user, params)
    end
  end

  defp create_release(conn, package, user, checksum, meta, body) do
    version = meta["version"]
    release_params = %{"app" => meta["app"], "version" => version,
                       "requirements" => meta["requirements"], "meta" => meta}

    if release = HexWeb.Repo.get_by(assoc(package, :releases), version: version) do
      update(conn, package, release, release_params, checksum, user, body)
    else
      create(conn, package, release_params, checksum, user, body)
    end
  end

  defp update(conn, package, release, release_params, checksum, user, body) do
    case Release.update(release, release_params, checksum) do
      {:ok, release} ->
        after_release(package, release.version, user, body)

        release = %{release | package: package}

        conn
        |> api_cache(:public)
        |> render(:show, release: release)
      {:error, errors} ->
        validation_failed(conn, errors)
    end
  end

  defp create(conn, package, release_params, checksum, user, body) do
    result =
      HexWeb.Repo.transaction(fn ->
        case Release.create(package, release_params, checksum) do
          {:ok, release} ->
            audit(conn, "release.publish", {package, release})
            release
          {:error, changeset} ->
            HexWeb.Repo.rollback(changeset)
        end
      end)

    case result do
      {:ok, release} ->
        after_release(package, release.version, user, body)

        release = %{release | package: package}
        location = release_url(conn, :show, package, release)

        conn
        |> put_resp_header("location", location)
        |> api_cache(:public)
        |> put_status(201)
        |> render(:show, release: release)
      {:error, errors} ->
        validation_failed(conn, errors)
    end
  end

  defp after_release(package, version, user, body) do
    task    = fn -> job(package, version, body) end
    success = fn -> :ok end
    failure = fn reason -> failure(package, version, user, reason) end
    HexWeb.Utils.task(task, success, failure)
  end

  defp job(package, version, body) do
    key = "tarballs/#{package.name}-#{version}"
    HexWeb.Store.put_release(package.name, version, body)
    HexWeb.CDN.purge_key(:fastly_hexrepo, key)
    HexWeb.RegistryBuilder.rebuild
  end

  defp failure(package, version, user, reason) do
    require Logger
    Logger.error "Package upload failed: #{inspect reason}"

    # TODO: Revert database changes

    # TODO: Move to mailer service
    HexWeb.Mailer.send(
      "publish_fail.html",
      "Hex.pm - ERROR when publishing #{package.name} v#{version}",
      [user.email],
      package: package.name,
      version: version,
      docs: false)
  end

  defp revert(release) do
    task = fn ->
      name    = release.package.name
      version = to_string(release.version)

      # Delete release tarball
      HexWeb.Store.delete_release("#{name}-#{version}.tar")

      # Delete relevant documentation (if it exists)
      if release.has_docs do
        paths = HexWeb.Store.list_docs_pages(Path.join(name, version))
        HexWeb.Store.delete_docs("#{name}-#{version}.tar.gz")
        Enum.each(paths, fn path ->
          HexWeb.Store.delete_docs_page(path)
        end)
      end

      HexWeb.RegistryBuilder.rebuild
    end

    # TODO: Send mails
    HexWeb.Utils.task(task, fn -> nil end, fn _ -> nil end)
  end
end
