defmodule Hexpm.Repository.Assets do
  def push_release(release, body) do
    opts = [
      acl: :public_read,
      cache_control: "public, max-age=604800",
      meta: [{"surrogate-key", tarball_cdn_key(release)}]
    ]
    Hexpm.Store.put(nil, :s3_bucket, tarball_store_key(release), body, opts)
    Hexpm.CDN.purge_key(:fastly_hexrepo, tarball_cdn_key(release))
  end

  def revert_release(release) do
    name = release.package.name
    version = to_string(release.version)

    # Delete release tarball
    Hexpm.Store.delete(nil, :s3_bucket, tarball_store_key(release))

    # Delete relevant documentation (if it exists)
    if release.has_docs do
      Hexpm.Store.delete(nil, :s3_bucket, docs_store_key(release))
      paths = Hexpm.Store.list(nil, :docs_bucket, Path.join(name, version))
      Hexpm.Store.delete_many(nil, :docs_bucket, Enum.to_list(paths))
      Hexpm.Repository.Sitemaps.publish_docs_sitemap()
    end
  end

  def push_docs_sitemap(sitemap) do
    opts = [
      acl: :public_read,
      content_type: "text/xml",
      cache_control: "public, max-age=300",
      meta: [{"surrogate-key", "sitemap"}]
    ]
    Hexpm.Store.put(nil, :docs_bucket, "sitemap.xml", sitemap, opts)
    Hexpm.CDN.purge_key(:fastly_hexdocs, "sitemap")
  end

  def push_docs(release, files, body, docs_for_latest_release) do
    name = release.package.name
    version = release.version
    package = release.package
    pre_release? = version.pre != []
    first_release? = package.docs_updated_at == nil

    files =
      Enum.flat_map(files, fn {path, data} ->
        versioned = {Path.join([name, to_string(version), path]), versioned_key(release), data}
        unversioned = {Path.join(name, path), unversioned_key(release), data}

        cond do
          pre_release? and not first_release? ->
            [versioned]
          first_release? || docs_for_latest_release ->
            [versioned, unversioned]
          true ->
            [versioned]
        end
      end)
    paths = MapSet.new(files, &elem(&1, 0))

    delete_old_docs(release, paths, docs_for_latest_release)
    put_docs_tarball(release, body)
    upload_new_files(files)
    purge_cache(release, docs_for_latest_release)
  end

  def revert_docs(release) do
    name = release.package.name
    version = to_string(release.version)
    paths = Hexpm.Store.list(nil, :docs_bucket, Path.join(name, version))

    Hexpm.Store.delete_many(nil, :docs_bucket, Enum.to_list(paths))

    Hexpm.Utils.multi_task([
      fn -> Hexpm.CDN.purge_key(:fastly_hexrepo, docs_cdn_key(release)) end,
      fn -> Hexpm.CDN.purge_key(:fastly_hexdocs, versioned_key(release)) end
    ])
  end

  defp put_docs_tarball(release, body) do
    surrogate_key = {"surrogate-key", docs_cdn_key(release)}
    surrogate_control = {"surrogate-control", "max-age=604800"}
    opts = [
      acl: :public_read,
      cache_control: "public, max-age=3600",
      meta: [surrogate_key, surrogate_control]
    ]

    Hexpm.Store.put(nil, :s3_bucket, docs_store_key(release), body, opts)
  end

  defp delete_old_docs(release, paths, docs_for_latest_release) do
    name = release.package.name
    version = release.version
    pre_release? = version.pre != []

    # Add "/" so that we don't get prefix matches, for example phoenix
    # would match phoenix_html
    existing_keys = Hexpm.Store.list(nil, :docs_bucket, "#{name}/")
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
          pre_release? ->
            []
          # Top-level docs, don't match version directories (/ecto/...)
          Version.parse(first) == :error && docs_for_latest_release ->
            [key]
          true ->
            []
        end
      end)
    Hexpm.Store.delete_many(nil, :docs_bucket, keys_to_delete)
  end

  defp upload_new_files(files) do
    Enum.map(files, fn {store_key, cdn_key, data} ->
      surrogate_key = {"surrogate-key", cdn_key}
      surrogate_control = {"surrogate-control", "max-age=604800"}

      opts =
        content_type(store_key)
        |> Keyword.put(:cache_control, "public, max-age=3600")
        |> Keyword.put(:meta, [surrogate_key, surrogate_control])
      {store_key, data, opts}
    end)
    |> Task.async_stream(fn {key, data, opts} ->
      Hexpm.Store.put(nil, :docs_bucket, key, data, opts)
    end, max_concurrency: 10, timeout: 10_000)
    |> Stream.run()
  end

  defp purge_cache(release, docs_for_latest_release) do
    first_release? = release.package.docs_updated_at == nil

    purge_tasks = [
      fn -> Hexpm.CDN.purge_key(:fastly_hexrepo, docs_cdn_key(release)) end,
      fn -> Hexpm.CDN.purge_key(:fastly_hexdocs, versioned_key(release)) end
    ]
    purge_tasks =
      if first_release? || docs_for_latest_release do
        [fn -> Hexpm.CDN.purge_key(:fastly_hexdocs, unversioned_key(release)) end | purge_tasks]
      else
        purge_tasks
      end

    Hexpm.Utils.multi_task(purge_tasks)
  end

  defp content_type(path) do
    case Path.extname(path) do
      "." <> ext -> [content_type: Plug.MIME.type(ext)]
      ""         -> []
    end
  end

  def tarball_cdn_key(release) do
    "tarballs/#{release.package.name}-#{release.version}"
  end

  def tarball_store_key(release) do
    "tarballs/#{release.package.name}-#{release.version}.tar"
  end

  def docs_cdn_key(release) do
    "docs/#{release.package.name}-#{release.version}"
  end

  def docs_store_key(release) do
    "docs/#{release.package.name}-#{release.version}.tar.gz"
  end

  def versioned_key(release) do
    "docspage/#{release.package.name}/#{release.version}"
  end

  def unversioned_key(release) do
    "docspage/#{release.package.name}"
  end
end
