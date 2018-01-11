defmodule Hexpm.Repository.Assets do
  alias Hexpm.Repository.Repository

  def push_release(release, body) do
    opts = [
      acl: store_acl(release.package.repository),
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

  def push_docs(release, files, body, all_versions) do
    name = release.package.name
    version = release.version
    latest_version = List.first(all_versions)
    pre_release? = version.pre != []
    first_release? = all_versions == []
    all_pre_releases? = Enum.all?(all_versions, &(&1.pre != []))
    latest_release? = first_release? or Version.compare(release.version, latest_version) in [:eq, :gt]
    publish_unversioned? = latest_release? and (not pre_release? or all_pre_releases?)

    files =
      Enum.flat_map(files, fn {path, data} ->
        versioned = {Path.join([name, to_string(version), path]), docspage_versioned_cdn_key(release), data}
        unversioned = {Path.join(name, path), docspage_unversioned_cdn_key(release), data}

        if publish_unversioned? do
          [versioned, unversioned]
        else
          [versioned]
        end
      end)
    paths = MapSet.new(files, &elem(&1, 0))

    delete_old_docs(release, paths, publish_unversioned?)
    put_docs_tarball(release, body)
    upload_new_files(release, files)
    purge_cache(release, publish_unversioned?)
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
      acl: store_acl(release.package.repository),
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
    keys_to_delete = Enum.filter(existing_keys, &delete_key?(&1, paths, name, version, publish_unversioned?))
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

  defp upload_new_files(release, files) do
    Enum.map(files, fn {store_key, cdn_key, data} ->
      surrogate_key = {"surrogate-key", cdn_key}
      surrogate_control = {"surrogate-control", "max-age=604800"}

      opts =
        content_type(store_key)
        |> Keyword.put(:acl, store_acl(release.package.repository))
        |> Keyword.put(:cache_control, "public, max-age=3600")
        |> Keyword.put(:meta, [surrogate_key, surrogate_control])
      {store_key, data, opts}
    end)
    |> Task.async_stream(fn {key, data, opts} ->
      Hexpm.Store.put(nil, :docs_bucket, key, data, opts)
    end, max_concurrency: 10, timeout: 10_000)
    |> Stream.run()
  end

  defp purge_cache(release, publish_unversioned?) do
    purge_tasks = [
      fn -> Hexpm.CDN.purge_key(:fastly_hexrepo, docs_cdn_key(release)) end,
      fn -> Hexpm.CDN.purge_key(:fastly_hexdocs, docspage_versioned_cdn_key(release)) end,
    ]
    purge_tasks =
      if publish_unversioned? do
        [fn -> Hexpm.CDN.purge_key(:fastly_hexdocs, docspage_unversioned_cdn_key(release)) end | purge_tasks]
      else
        purge_tasks
      end

    Hexpm.Utils.multi_task(purge_tasks)
  end

  defp content_type(path) do
    case Path.extname(path) do
      "." <> ext -> [content_type: MIME.type(ext)]
      ""         -> []
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
    repo = release.package.repository
    if repo.id == 1 do
      ""
    else
      "#{repo.name}-"
    end
  end

  defp repository_store_key(release) do
    repo = release.package.repository
    if repo.id == 1 do
      ""
    else
      "repos/#{repo.name}/"
    end
  end

  defp store_acl(%Repository{public: true}), do: :public_read
  defp store_acl(%Repository{public: false}), do: :private
end
