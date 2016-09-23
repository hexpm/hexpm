defmodule HexWeb.Assets do
  def push_release(release, body) do
    opts = [acl: :public_read, cache_control: "public, max-age=604800", meta: [{"surrogate-key", tarball_cdn_key(release)}]]
    HexWeb.Store.put(nil, :s3_bucket, tarball_store_key(release), body, opts)
    HexWeb.CDN.purge_key(:fastly_hexrepo, tarball_cdn_key(release))
  end

  def revert_release(release) do
    name    = release.package.name
    version = to_string(release.version)

    # Delete release tarball
    HexWeb.Store.delete(nil, :s3_bucket, tarball_store_key(release), [])

    # Delete relevant documentation (if it exists)
    if release.has_docs do
      HexWeb.Store.delete(nil, :s3_bucket, "docs/#{name}-#{version}.tar.gz", [])
      paths = HexWeb.Store.list(nil, :docs_bucket, Path.join(name, version))
      HexWeb.Store.delete_many(nil, :docs_bucket, Enum.to_list(paths), [])
      HexWeb.Sitemaps.publish_docs_sitemap()
    end
  end

  def push_docs_sitemap(sitemap) do
    opts = [acl: :public_read, content_type: "text/xml",
            cache_control: "public, max-age=300",
            meta: [{"surrogate-key", "sitemap"}]]
    HexWeb.Store.put(nil, :docs_bucket, "sitemap.xml", sitemap, opts)
    HexWeb.CDN.purge_key(:fastly_hexdocs, "sitemap")
  end

  def push_docs(release, files, body, docs_for_latest_release) do
    name = release.package.name
    version = release.version
    package = release.package
    pre_release    = version.pre != []
    first_release  = package.docs_updated_at == nil
    unversioned_key = "docspage/#{package.name}"
    versioned_key   = "docspage/#{package.name}/#{release.version}"

    files =
      Enum.flat_map(files, fn {path, data} ->
        versioned = {Path.join([name, to_string(version), path]), versioned_key, data}
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

    delete_old_docs(release, paths, docs_for_latest_release)
    put_tarball(release, body)
    upload_new_files(files)
    purge_cache(release, docs_for_latest_release)
  end

  def revert_docs(release) do
    name    = release.package.name
    version = to_string(release.version)
    paths   = HexWeb.Store.list(nil, :docs_bucket, Path.join(name, version))

    HexWeb.Store.delete(nil, :s3_bucket, "tarballs/#{name}-#{version}.tar.gz", [])
    HexWeb.Store.delete_many(nil, :docs_bucket, Enum.to_list(paths), [])

    HexWeb.Utils.multi_task([
      fn -> HexWeb.CDN.purge_key(:fastly_hexrepo, "docs/#{name}-#{version}") end,
      fn -> HexWeb.CDN.purge_key(:fastly_hexdocs, "docspage/#{name}/#{version}") end
    ])
  end

  defp put_tarball(release, body) do
    # TODO: Cache and add surrogate key
    opts = [acl: :public_read]
    HexWeb.Store.put(nil, :s3_bucket, "docs/#{release.package.name}-#{release.version}.tar.gz", body, opts)
  end

  defp delete_old_docs(release, paths, docs_for_latest_release) do
    name = release.package.name
    version = release.version
    pre_release    = version.pre != []

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
  end

  defp upload_new_files(files) do
    objects =
      Enum.map(files, fn {store_key, cdn_key, data} ->
        opts =
          content_type(store_key)
          |> Keyword.put(:cache_control, "public, max-age=604800")
          |> Keyword.put(:meta, [{"surrogate-key", cdn_key}])
        {store_key, data, opts}
    end)
    HexWeb.Store.put_many(nil, :docs_bucket, objects, [])
  end

  defp purge_cache(release, docs_for_latest_release) do
    first_release   = release.package.docs_updated_at == nil
    unversioned_key = "docspage/#{release.package.name}"
    versioned_key   = "docspage/#{release.package.name}/#{release.version}"

    purge_tasks = [
      fn -> HexWeb.CDN.purge_key(:fastly_hexrepo, "docs/#{release.package.name}-#{release.version}") end,
      fn -> HexWeb.CDN.purge_key(:fastly_hexdocs, versioned_key) end
    ]
    purge_tasks =
      if first_release || docs_for_latest_release do
        [fn -> HexWeb.CDN.purge_key(:fastly_hexdocs, unversioned_key) end | purge_tasks]
      else
        purge_tasks
      end

    HexWeb.Utils.multi_task(purge_tasks)
  end

  defp content_type(path) do
    case Path.extname(path) do
      "." <> ext -> [content_type: Plug.MIME.type(ext)]
      ""         -> []
    end
  end

  def tarball_cdn_key(release), do: "tarballs/#{release.package.name}-#{release.version}"

  def tarball_store_key(release), do: "tarballs/#{release.package.name}-#{release.version}.tar"
end
