defmodule HexWeb.API.ReleaseController do
  use HexWeb.Web, :controller

  @publish_timeout 60_000

  plug :fetch_release when action == :show

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
    {:ok, conn} = HexWeb.Repo.transaction_with_isolation(fn ->

      conn =
        conn
        |> fetch_release([])
        |> authorize(fun: &package_owner?/2)

      if conn.halted do
        conn
      else
        package = conn.assigns.package
        release = conn.assigns.release

        case HexWeb.Repo.delete(Release.delete(release)) do
          {:ok, _} ->
            if Repo.aggregate(assoc(package, :releases), :count, :id) == 0 do
              HexWeb.Repo.delete!(package)
            end

            HexWeb.Repo.insert!(audit(conn, "release.revert", {package, release}))
            revert(release)

            conn
            |> api_cache(:private)
            |> send_resp(204, "")
          {:error, changeset} ->
            validation_failed(conn, changeset)
        end
      end
    end, level: :serializable, timeout: @publish_timeout)

    conn
  end

  defp handle_tarball(conn, package, user, body) do
    {:ok, conn} = HexWeb.Repo.transaction(fn ->
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
    end, timeout: @publish_timeout)

    conn
  end

  defp create_package(user, package, params) do
    name = params["name"]
    package = package || HexWeb.Repo.get_by(Package, name: name)

    if package do
      Package.update(package, params)
      |> HexWeb.Repo.update
    else
      Package.build(user, params)
      |> HexWeb.Repo.insert
    end
  end

  defp create_release(conn, package, user, checksum, meta, body) do
    version = meta["version"]
    release_params = %{
      "app" => meta["app"],
      "version" => version,
      "requirements" => meta["requirements"],
      "meta" => meta}
    |> normalize_params

    if release = HexWeb.Repo.get_by(assoc(package, :releases), version: version) do
      update(conn, package, release, release_params, checksum, user, body)
    else
      create(conn, package, release_params, checksum, user, body)
    end
  end

  defp update(conn, package, release, release_params, checksum, user, body) do
    release = HexWeb.Repo.preload(release, requirements: Release.requirements(release))

    case Release.update(release, release_params, checksum) |> HexWeb.Repo.update do
      {:ok, release} ->
        audit(user, "release.publish", {package, release})
        |> HexWeb.Repo.insert!

        after_release(package, release.version, body)

        conn
        |> api_cache(:public)
        |> render(:show, release: %{release | package: package})
      {:error, errors} ->
        validation_failed(conn, errors)
    end
  end

  defp create(conn, package, params, checksum, user, body) do
    multi =
      Ecto.Multi.new
      |> Ecto.Multi.insert(:release, Release.build(package, params, checksum))
      |> Ecto.Multi.insert(:log, fn %{release: release} -> audit(user, "release.publish", {package, release}) end)

    case HexWeb.Repo.transaction(multi) do
      {:ok, %{release: release}} ->
        after_release(package, release.version, body)

        release = %{release | package: package}
        location = release_url(conn, :show, package, release)

        conn
        |> put_resp_header("location", location)
        |> api_cache(:public)
        |> put_status(201)
        |> render(:show, release: release)
      {:error, :release, changeset, _} ->
        validation_failed(conn, normalize_errors(changeset))
    end
  end

  # Turn `%{"ecto" => %{"app" => "...", ...}}` into:
  #      `[%{"name" => "ecto", "app" => "...", ...}]` for cast_assoc
  defp normalize_params(%{"requirements" => requirements} = params) when is_map(requirements) do
    requirements =
      Enum.map(requirements, fn
        {name, map} -> Map.put(map, "name", name)
      end)

    %{params | "requirements" => requirements}
  end
  defp normalize_params(params), do: params

  defp normalize_errors(%{changes: %{requirements: requirements}} = changeset) do
    requirements =
      Enum.map(requirements, fn
        %{errors: errors} = req ->
          name = Ecto.Changeset.get_change(req, :name)
          %{req | errors: for({_, v} <- errors, do: {name, v}, into: %{})}
      end)

    put_in(changeset.changes.requirements, requirements)
  end
  defp normalize_errors(changeset), do: changeset

  defp after_release(package, version, body) do
    cdn_key = "tarballs/#{package.name}-#{version}"
    store_key = "tarballs/#{package.name}-#{version}.tar"
    opts = [acl: :public_read, cache_control: "public, max-age=604800", meta: [{"surrogate-key", cdn_key}]]
    HexWeb.Store.put(nil, :s3_bucket, store_key, body, opts)
    HexWeb.CDN.purge_key(:fastly_hexrepo, cdn_key)
    HexWeb.RegistryBuilder.rebuild
  end

  defp revert(release) do
    name    = release.package.name
    version = to_string(release.version)
    key     = "tarballs/#{name}-#{version}.tar"

    # Delete release tarball
    HexWeb.Store.delete(nil, :s3_bucket, key)

    # Delete relevant documentation (if it exists)
    if release.has_docs do
      HexWeb.Store.delete(nil, :s3_bucket, "docs/#{name}-#{version}.tar.gz")
      paths = HexWeb.Store.list(nil, :docs_bucket, Path.join(name, version))
      HexWeb.Store.delete(nil, :docs_bucket, Enum.to_list(paths))
      HexWeb.API.DocsController.publish_sitemap
    end

    HexWeb.RegistryBuilder.rebuild
  end
end
