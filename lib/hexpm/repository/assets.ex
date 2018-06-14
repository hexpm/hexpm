defmodule Hexpm.Repository.Assets do
  def push_release(release, body) do
    opts = [
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

  def push_hexdocs(release, files, all_versions) do
    name = release.package.name
    pre_release? = release.version.pre != []
    first_release? = all_versions == []
    all_pre_releases? = Enum.all?(all_versions, &(&1.pre != []))

    publish_unversioned? =
      cond do
        first_release? ->
          true

        all_pre_releases? ->
          latest_version = List.first(all_versions)
          Version.compare(release.version, latest_version) in [:eq, :gt]

        pre_release? ->
          false

        true ->
          nonpre_versions = Enum.filter(all_versions, &(&1.pre == []))
          latest_version = List.first(nonpre_versions)
          Version.compare(release.version, latest_version) in [:eq, :gt]
      end

    files =
      Enum.flat_map(files, fn {path, data} ->
        versioned_path = Path.join([name, to_string(release.version), path])
        versioned = {versioned_path, docspage_versioned_cdn_key(release), data}

        unversioned_path = Path.join(name, path)
        unversioned = {unversioned_path, docspage_unversioned_cdn_key(release), data}

        if publish_unversioned? do
          [versioned, unversioned]
        else
          [versioned]
        end
      end)

    paths = MapSet.new(files, &elem(&1, 0))

    delete_old_docs(release, paths, publish_unversioned?)
    upload_new_files(files)
    purge_hexdocs_cache(release, publish_unversioned?)
  end

  def push_docs_tarball(release, body) do
    put_docs_tarball(release, body)
    purge_docs_tarball_cache(release)
  end

  def revert_docs(release) do
    name = release.package.name
    version = to_string(release.version)
    paths = Hexpm.Store.list(nil, :docs_bucket, Path.join(name, version))

    Hexpm.Store.delete_many(nil, :docs_bucket, Enum.to_list(paths))

    Hexpm.Utils.multi_task([
      fn -> Hexpm.CDN.purge_key(:fastly_hexrepo, docs_cdn_key(release)) end,
      fn -> Hexpm.CDN.purge_key(:fastly_hexdocs, docspage_versioned_cdn_key(release)) end
    ])
  end

  defp put_docs_tarball(release, body) do
    surrogate_key = {"surrogate-key", docs_cdn_key(release)}
    surrogate_control = {"surrogate-control", "max-age=604800"}

    opts = [
      cache_control: "public, max-age=3600",
      meta: [surrogate_key, surrogate_control]
    ]

    Hexpm.Store.put(nil, :s3_bucket, docs_store_key(release), body, opts)
  end

  defp delete_old_docs(release, paths, publish_unversioned?) do
    name = release.package.name
    version = release.version

    # Add "/" so that we don't get prefix matches, for example phoenix
    # would match phoenix_html
    existing_keys = Hexpm.Store.list(nil, :docs_bucket, "#{name}/")

    keys_to_delete =
      Enum.filter(existing_keys, &delete_key?(&1, paths, name, version, publish_unversioned?))

    Hexpm.Store.delete_many(nil, :docs_bucket, keys_to_delete)
  end

  defp delete_key?(key, paths, name, version, publish_unversioned?) do
    # Don't delete if we are going to overwrite with new files, this
    # removes the downtime between a deleted and added page
    if key in paths do
      false
    else
      first = Path.relative_to(key, name) |> Path.split() |> hd()

      case Version.parse(first) do
        {:ok, first} ->
          # Current (/ecto/0.8.1/...)
          Version.compare(first, version) == :eq

        :error ->
          # Top-level docs, don't match version directories (/ecto/...)
          publish_unversioned?
      end
    end
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
    |> Task.async_stream(
      fn {key, data, opts} ->
        Hexpm.Store.put(nil, :docs_bucket, key, data, opts)
      end,
      max_concurrency: 10,
      timeout: 10_000
    )
    |> Stream.run()
  end

  defp purge_hexdocs_cache(release, publish_unversioned?) do
    if publish_unversioned? do
      Hexpm.Utils.multi_task([
        fn -> purge_versioned_docspage(release) end,
        fn -> purge_unversioned_docspage(release) end
      ])
    else
      Hexpm.Utils.multi_task([fn -> purge_versioned_docspage(release) end])
    end
  end

  defp purge_versioned_docspage(release) do
    Hexpm.CDN.purge_key(:fastly_hexdocs, docspage_versioned_cdn_key(release))
  end

  defp purge_unversioned_docspage(release) do
    Hexpm.CDN.purge_key(:fastly_hexdocs, docspage_unversioned_cdn_key(release))
  end

  defp purge_docs_tarball_cache(release) do
    Hexpm.CDN.purge_key(:fastly_hexrepo, docs_cdn_key(release))
  end

  defp content_type(path) do
    case Path.extname(path) do
      "." <> ext -> [content_type: MIME.type(ext)]
      "" -> []
    end
  end

  def tarball_cdn_key(release) do
    "tarballs/#{repository_cdn_key(release)}#{release.package.name}-#{release.version}"
  end

  def tarball_store_key(release) do
    "#{repository_store_key(release)}tarballs/#{release.package.name}-#{release.version}.tar"
  end

  def docs_cdn_key(release) do
    "docs/#{repository_cdn_key(release)}#{release.package.name}-#{release.version}"
  end

  def docs_store_key(release) do
    "#{repository_store_key(release)}docs/#{release.package.name}-#{release.version}.tar.gz"
  end

  def docspage_versioned_cdn_key(release) do
    "docspage/#{repository_cdn_key(release)}#{release.package.name}/#{release.version}"
  end

  def docspage_unversioned_cdn_key(release) do
    "docspage/#{repository_cdn_key(release)}#{release.package.name}"
  end

  defp repository_cdn_key(release) do
    organization = release.package.organization

    if organization.id == 1 do
      ""
    else
      "#{organization.name}-"
    end
  end

  defp repository_store_key(release) do
    organization = release.package.organization

    if organization.id == 1 do
      ""
    else
      "repos/#{organization.name}/"
    end
  end
end
