defmodule Hexpm.Hexdocs.Bucket do
  require Logger

  alias Hexpm.Hexdocs.{Debouncer, FileRewriter, Utils}

  @special_package_names Map.keys(Application.compile_env!(:hexpm, :hexdocs_special_packages))
  @gcs_put_debounce Application.compile_env!(:hexpm, :hexdocs_gcs_put_debounce)

  def upload_index_sitemap(sitemap),
    do: upload_content("sitemap", "sitemap.xml", "text/xml", sitemap)

  def upload_package_sitemap(package, sitemap),
    do: upload_content("sitemap/#{package}", "#{package}/sitemap.xml", "text/xml", sitemap)

  def upload_package_names_csv(contents),
    do: upload_content("package_names.csv", "package_names.csv", "text/csv", contents)

  defp upload_content(key, path, content_type, content) do
    opts = [
      content_type: content_type,
      cache_control: "public, max-age=3600",
      meta: [{"surrogate-key", key}]
    ]

    Hexpm.Store.put(:docs_bucket, path, content, opts)
    purge("hexpm", [key])
  end

  def upload(repository, package, version, all_versions, retired_versions, dir, files) do
    upload_type =
      if Utils.latest_version?(package, version, all_versions), do: :both, else: :versioned

    upload_files = list_upload_files(repository, package, version, dir, files, upload_type)
    paths = MapSet.new(upload_files, &elem(&1, 0))

    upload_new_files(upload_files)
    delete_old_docs(repository, package, [version], paths, upload_type)

    Debouncer.debounce(Debouncer, {:docs_config, repository, package}, @gcs_put_debounce, fn ->
      config =
        build_docs_config(
          repository,
          package,
          version,
          all_versions,
          retired_versions,
          dir,
          files
        )

      upload_new_files([config])
    end)

    purge_hexdocs_cache(repository, package, [version], upload_type)
    purge(repository, [docs_config_cdn_key(repository, package)])
  end

  defp build_docs_config(repository, package, _version, _versions, _retired, dir, files)
       when package in @special_package_names do
    data =
      if "docs_config.js" in files, do: File.read!(Path.join(dir, "docs_config.js")), else: ""

    path = repository_path(repository, Path.join(package, "docs_config.js"))
    {path, docs_config_cdn_key(repository, package), data, public?(repository)}
  end

  defp build_docs_config(repository, package, version, versions, retired, _dir, _files) do
    versions =
      if version in versions,
        do: versions,
        else: Enum.sort([version | versions], {:desc, Version})

    latest = Utils.latest_version(versions)

    versions =
      Enum.map(versions, fn entry ->
        value = %{
          version: "v#{entry}",
          url: Hexpm.Utils.docs_html_url(repository, package, "/#{entry}")
        }

        value = if latest == entry, do: Map.put(value, :latest, true), else: value
        if entry in retired, do: Map.put(value, :retired, true), else: value
      end)

    search = if repository == "hexpm", do: [%{name: package, version: to_string(version)}]

    data = [
      "var versionNodes = ",
      Jason.encode_to_iodata!(versions),
      ";\n",
      if(search, do: ["var searchNodes = ", Jason.encode_to_iodata!(search), ";"], else: [])
    ]

    path = repository_path(repository, Path.join(package, "docs_config.js"))
    {path, docs_config_cdn_key(repository, package), data, public?(repository)}
  end

  def delete(repository, package, version, all_versions) do
    deleting_latest? = Utils.latest_version?(package, version, all_versions)
    new_latest = Utils.latest_version(all_versions -- [version])

    cond do
      deleting_latest? and new_latest ->
        key = build_key(repository, package, new_latest)
        tarball_path = Hexpm.TmpDir.tmp_file("docs-tarball")

        case Hexpm.Store.get_to_file(:repo_bucket, key, tarball_path) do
          :ok ->
            {dir, files} =
              Hexpm.Hexdocs.Tar.unpack_to_dir!({:file, tarball_path},
                repository: repository,
                package: package,
                version: new_latest
              )

            FileRewriter.rewrite_files(dir, files)
            uploads = list_upload_files(repository, package, new_latest, dir, files, :both)
            paths = MapSet.new(uploads, &elem(&1, 0))
            versions = [version, new_latest]
            upload_new_files(uploads)
            delete_old_docs(repository, package, versions, paths, :both)
            purge_hexdocs_cache(repository, package, versions, :both)

          nil ->
            raise "Hexdocs archive not found in store: #{key}"
        end

      deleting_latest? ->
        delete_old_docs(repository, package, [version], [], :both)
        purge_hexdocs_cache(repository, package, [version], :both)

      true ->
        delete_old_docs(repository, package, [version], [], :versioned)
        purge_hexdocs_cache(repository, package, [version], :versioned)
    end
  end

  defp build_key("hexpm", package, version), do: Path.join("docs", "#{package}-#{version}.tar.gz")

  defp build_key(repository, package, version),
    do: Path.join(["repos", repository, "docs", "#{package}-#{version}.tar.gz"])

  defp list_upload_files(repository, package, version, dir, files, upload_type) do
    Enum.flat_map(files, fn
      "docs_config.js" ->
        []

      path ->
        source = Path.join(dir, path)

        versioned_path =
          repository_path(repository, Path.join([package, to_string(version), path]))

        versioned =
          {versioned_path, versioned_cdn_key(repository, package, version), {:file, source},
           public?(repository)}

        unversioned_path = repository_path(repository, Path.join([package, path]))

        unversioned =
          {unversioned_path, unversioned_cdn_key(repository, package), {:file, source},
           public?(repository)}

        case upload_type do
          :both -> [versioned, unversioned]
          :versioned -> [versioned]
          :unversioned -> [unversioned]
        end
    end)
  end

  defp upload_new_files(files) do
    files
    |> Enum.map(fn {store_key, cdn_key, data, public?} ->
      opts =
        content_type(store_key)
        |> Keyword.put(
          :cache_control,
          if(public?, do: "public, max-age=3600", else: "private, max-age=3600")
        )
        |> Keyword.put(:meta, [
          {"surrogate-key", cdn_key},
          {"surrogate-control", "public, max-age=604800"}
        ])

      {bucket(public?), store_key, data, opts}
    end)
    |> Task.async_stream(
      fn
        {bucket, key, {:file, source}, opts} -> Hexpm.Store.put_file(bucket, key, source, opts)
        {bucket, key, data, opts} -> Hexpm.Store.put(bucket, key, data, opts)
      end,
      max_concurrency: 10,
      timeout: 60_000
    )
    |> Hexpm.Utils.raise_async_stream_error()
    |> Stream.run()
  end

  defp delete_old_docs(repository, package, versions, paths, upload_type) do
    bucket = bucket(public?(repository))

    existing =
      case {upload_type, versions} do
        {:both, _} ->
          Hexpm.Store.list(bucket, repository_path(repository, "#{package}/"))

        {:versioned, [version]} ->
          Hexpm.Store.list(bucket, repository_path(repository, "#{package}/#{version}/"))
      end

    keys =
      Enum.filter(existing, &delete_key?(&1, paths, repository, package, versions, upload_type))

    Hexpm.Store.delete_many(bucket, keys)
  end

  defp delete_key?(key, paths, repository, package, versions, upload_type) do
    if key in paths do
      false
    else
      first =
        key |> Path.relative_to(repository_path(repository, package)) |> Path.split() |> hd()

      case Version.parse(first) do
        {:ok, _version} ->
          Enum.any?(versions, &(is_struct(&1, Version) and Version.compare(first, &1) == :eq))

        :error when package in @special_package_names ->
          first != "main" and Version.parse(first <> ".0") == :error

        :error ->
          upload_type in [:both, :unversioned]
      end
    end
  end

  defp content_type(path) do
    case Path.extname(path) do
      "." <> extension -> [content_type: MIME.type(extension)]
      "" -> []
    end
  end

  defp bucket(true), do: :docs_bucket
  defp bucket(false), do: :docs_private_bucket
  defp repository_path("hexpm", path), do: path
  defp repository_path(repository, path), do: repository <> "/" <> path
  defp public?("hexpm"), do: true
  defp public?(_repository), do: false

  defp purge_hexdocs_cache(repository, package, versions, :both) do
    keys = Enum.map(versions, &versioned_cdn_key(repository, package, &1))
    purge(repository, [unversioned_cdn_key(repository, package) | keys])
  end

  defp purge_hexdocs_cache(repository, package, versions, :versioned) do
    purge(repository, Enum.map(versions, &versioned_cdn_key(repository, package, &1)))
  end

  defp versioned_cdn_key(repository, package, version),
    do: "docspage/#{repository_cdn_key(repository)}#{package}/#{version}"

  defp unversioned_cdn_key(repository, package),
    do: "docspage/#{repository_cdn_key(repository)}#{package}"

  defp docs_config_cdn_key(repository, package),
    do: "docspage/#{repository_cdn_key(repository)}#{package}/docs_config.js"

  defp repository_cdn_key("hexpm"), do: ""
  defp repository_cdn_key(repository), do: repository <> "-"

  defp purge(repository, keys) do
    service = if public?(repository), do: :fastly_hexdocs, else: :fastly_hexdocs_private
    Logger.info("Purging #{service} #{Enum.join(keys, " ")}")
    Hexpm.CDN.purge_key(service, keys)
  end
end
