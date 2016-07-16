defmodule HexWeb.API.DocsController do
  use HexWeb.Web, :controller

  @zlib_magic 16 + 15
  @compressed_max_size 8 * 1024 * 1024
  @uncompressed_max_size 64 * 1024 * 1024

  plug :fetch_release
  plug :authorize, [fun: &package_owner?/2] when action != :show

  def show(conn, _params) do
    package = conn.assigns.package
    release = conn.assigns.release

    if release.has_docs do
      redirect(conn, external: HexWeb.Utils.docs_tarball_url(package, release))
    else
      not_found(conn)
    end
  end

  def create(conn, %{"body" => body}) do
    package = conn.assigns.package
    release = conn.assigns.release
    handle_tarball(conn, package, release, body)
  end

  def delete(conn, _params) do
    revert(conn, conn.assigns.release)

    conn
    |> api_cache(:private)
    |> send_resp(204, "")
  end

  defp handle_tarball(conn, package, release, body) do
    case parse_tarball(body) do
      {:ok, {files, body}} ->
        upload_docs(conn, package, release, files, body)
        location = HexWeb.Utils.docs_tarball_url(package, release)

        conn
        |> put_resp_header("location", location)
        |> api_cache(:public)
        |> send_resp(201, "")
      {:error, errors} ->
        validation_failed(conn, [tar: errors])
    end
  end

  defp parse_tarball(body) do
    with {:ok, data} <- unzip(body),
         {:ok, files} <- :erl_tar.extract({:binary, data}, [:memory]),
         files = Enum.map(files, fn {path, data} -> {List.to_string(path), data} end),
         :ok <- check_version_dirs(files),
         do: {:ok, {files, body}}
  end

  defp unzip(data) when byte_size(data) > @compressed_max_size do
    {:error, "too big"}
  end

  defp unzip(data) do
    stream = :zlib.open

    try do
      :zlib.inflateInit(stream, @zlib_magic)
      # limit single uncompressed chunk size to 512kb
      :zlib.setBufSize(stream, 512 * 1024)
      uncompressed = unzip_inflate(stream, "", 0, :zlib.inflateChunk(stream, data))
      :zlib.inflateEnd(stream)
      uncompressed
    after
      :zlib.close(stream)
    end
  end

  defp unzip_inflate(_stream, _data, total, _) when total > @uncompressed_max_size do
    {:error, "too big"}
  end

  defp unzip_inflate(stream, data, total, {:more, uncompressed}) do
    total = total + byte_size(uncompressed)
    unzip_inflate(stream, [data|uncompressed], total, :zlib.inflateChunk(stream))
  end

  defp unzip_inflate(_stream, data, _total, uncompressed) do
    {:ok, IO.iodata_to_binary([data|uncompressed])}
  end

  def upload_docs(conn, package, release, files, body) do
    name            = package.name
    version         = to_string(release.version)
    unversioned_key = "docspage/#{package.name}"
    versioned_key   = "docspage/#{package.name}/#{release.version}"
    pre_release     = release.version.pre != []
    first_release   = package.docs_updated_at == nil

    latest_version = from(r in Release.all(package), select: r.version, where: r.has_docs == true or r.version == ^version)
                     |> HexWeb.Repo.all
                     |> Enum.reject(fn(version) -> version.pre != [] end)
                     |> Enum.sort(&Version.compare(&1, &2) == :gt)
                     |> List.first

    docs_for_latest_release = (latest_version != nil) && (release.version == latest_version)
    files =
      Enum.flat_map(files, fn {path, data} ->
        versioned = {Path.join([name, version, path]), versioned_key, data}
        unversioned = {Path.join(name, path), unversioned_key, data}

        cond do
          pre_release && !first_release ->
            [versioned]
          first_release || docs_for_latest_release ->
            [versioned, unversioned]
          true ->
            [versioned]
        end
      end)
    paths = MapSet.new(files, &elem(&1, 0))

    # Delete old files
    # Add "/" so that we don't get prefix matches, for example phoenix
    # would match phoenix_html
    existing_keys = HexWeb.Store.list(nil, :docs_bucket, "#{name}/")
    keys_to_delete =
      Enum.flat_map(existing_keys, fn key ->
        first = Path.relative_to(key, name) |> Path.split |> hd
        cond do
          # Don't delete if we are going to overwrite with new files, this
          # removes the downtime between a deleted and added page
          key in paths ->
            []
          # Current (/ecto/0.8.1/...)
          first == version ->
            [key]
          # Top-level docs, don't overwrite for pre-releases
          pre_release == true ->
            []
          # Top-level docs, don't match version directories (/ecto/...)
          Version.parse(first) == :error && docs_for_latest_release ->
            [key]
          true ->
            []
        end
      end)
    HexWeb.Store.delete_many(nil, :docs_bucket, keys_to_delete, [])

    # Put tarball
    # TODO: Cache and add surrogate key
    opts = [acl: :public_read]
    HexWeb.Store.put(nil, :s3_bucket, "docs/#{name}-#{version}.tar.gz", body, opts)

    # Upload new files
    objects =
      Enum.map(files, fn {store_key, cdn_key, data} ->
        opts =
          content_type(store_key)
          |> Keyword.put(:cache_control, "public, max-age=604800")
          |> Keyword.put(:meta, [{"surrogate-key", cdn_key}])
        {store_key, data, opts}
    end)
    HexWeb.Store.put_many(nil, :docs_bucket, objects, [])

    # Purge cache
    purge_tasks = [
      fn -> HexWeb.CDN.purge_key(:fastly_hexrepo, "docs/#{name}-#{version}") end,
      fn -> HexWeb.CDN.purge_key(:fastly_hexdocs, versioned_key) end
    ]
    purge_tasks =
      if first_release || docs_for_latest_release do
        [fn -> HexWeb.CDN.purge_key(:fastly_hexdocs, unversioned_key) end | purge_tasks]
      else
        purge_tasks
      end

    HexWeb.Utils.multi_task(purge_tasks)

    multi =
      Ecto.Multi.new
      |> Ecto.Multi.update(:release, Ecto.Changeset.change(release, has_docs: true))
      |> Ecto.Multi.update(:package, Ecto.Changeset.change(release.package, docs_updated_at: Ecto.DateTime.utc))
      |> audit(conn, "docs.publish", {package, release})

    {:ok, _} = HexWeb.Repo.transaction(multi)

    publish_sitemap()
  end

  defp content_type(path) do
    case Path.extname(path) do
      "." <> ext -> [content_type: Plug.MIME.type(ext)]
      ""         -> []
    end
  end

  defp check_version_dirs(files) do
    result = Enum.all?(files, fn {path, _data} ->
      first = Path.split(path) |> hd
      Version.parse(first) == :error
    end)

    if result,
      do: :ok,
    else: {:error, "directory name not allowed to match a semver version"}
  end

  def revert(conn, release) do
    name    = release.package.name
    version = to_string(release.version)
    paths   = HexWeb.Store.list(nil, :docs_bucket, Path.join(name, version))

    HexWeb.Store.delete(nil, :s3_bucket, "tarballs/#{name}-#{version}.tar.gz", [])
    HexWeb.Store.delete_many(nil, :docs_bucket, Enum.to_list(paths), [])

    multi =
      Ecto.Multi.new
      |> Ecto.Multi.update(:release, Ecto.Changeset.change(release, has_docs: false))
      |> Ecto.Multi.update(:package, Ecto.Changeset.change(release.package, docs_updated_at: Ecto.DateTime.utc))
      |> audit(conn, "docs.revert", {release.package, release})

    {:ok, _} = HexWeb.Repo.transaction(multi)

    HexWeb.Utils.multi_task([
      fn -> HexWeb.CDN.purge_key(:fastly_hexrepo, "docs/#{name}-#{version}") end,
      fn -> HexWeb.CDN.purge_key(:fastly_hexdocs, "docspage/#{name}/#{version}") end
    ])

    publish_sitemap()
  end

  def publish_sitemap do
    packages = Package.docs_sitemap |> HexWeb.Repo.all
    sitemap = HexWeb.SitemapView.render("docs_sitemap.xml", packages: packages)

    # TODO: Cache and surrogate key
    opts = [acl: :public_read, content_type: "text/xml"]
    HexWeb.Store.put(nil, :docs_bucket, "sitemap.xml", sitemap, opts)
  end
end
