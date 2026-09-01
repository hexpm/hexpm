defmodule Hexpm.Hexdocs.Bucket do
  alias Hexpm.Hexdocs.{Debouncer, Utils}

  @special_package_names Map.keys(Application.compile_env!(:hexpm, :hexdocs_special_packages))
  @gcs_put_debounce Application.compile_env!(:hexpm, :hexdocs_gcs_put_debounce)

  def upload_index_sitemap(sitemap) do
    upload_content(
      "sitemap",
      "sitemap.xml",
      "text/xml",
      sitemap,
      Hexpm.Utils.docs_url("sitemap.xml")
    )
  end

  # The CDN redirects hexdocs.pm/<package>/... to the package subdomain, so
  # the check has to fetch the sitemap where it is served.
  def upload_package_sitemap(package, sitemap) do
    upload_content(
      "sitemap/#{package}",
      "#{package}/sitemap.xml",
      "text/xml",
      sitemap,
      Hexpm.Utils.docs_html_url("hexpm", package, "/sitemap.xml")
    )
  end

  def upload_package_names_csv(contents) do
    upload_content(
      "package_names.csv",
      "package_names.csv",
      "text/csv",
      contents,
      Hexpm.Utils.docs_url("package_names.csv")
    )
  end

  defp upload_content(key, path, content_type, content, url) do
    opts = [
      content_type: content_type,
      cache_control: "public, max-age=3600",
      meta: [{"surrogate-key", key}]
    ]

    {:ok, %{etag: etag}} = Hexpm.Store.put(:docs_bucket, path, content, opts)
    purge("hexpm", [key], [%{url: url, etag: etag}])
  end

  def upload(repository, package, version, all_versions, retired_versions, dir, files) do
    upload_type =
      if Utils.latest_version?(package, version, all_versions), do: :both, else: :versioned

    upload_files = list_upload_files(repository, package, version, dir, files, upload_type)
    paths = MapSet.new(upload_files, &elem(&1, 0))

    uploaded = upload_new_files(upload_files)
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

    purge_hexdocs_cache(
      repository,
      package,
      [version],
      upload_type,
      page_targets(repository, uploaded)
    )

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
      JSON.encode_to_iodata!(versions),
      ";\n",
      if(search, do: ["var searchNodes = ", JSON.encode_to_iodata!(search), ";"], else: [])
    ]

    path = repository_path(repository, Path.join(package, "docs_config.js"))
    {path, docs_config_cdn_key(repository, package), data, public?(repository)}
  end

  def delete(repository, package, version, :both) do
    delete_old_docs(repository, package, [version], [], :both)
    targets = deleted_page_targets(repository, package, [version, nil])
    purge_hexdocs_cache(repository, package, [version], :both, targets)
  end

  def delete(repository, package, version, :versioned) do
    delete_old_docs(repository, package, [version], [], :versioned)
    targets = deleted_page_targets(repository, package, [version])
    purge_hexdocs_cache(repository, package, [version], :versioned, targets)
  end

  @doc "Replaces the removed latest `version` with `new_latest`, unpacked in `dir`."
  def promote(repository, package, version, new_latest, dir, files) do
    uploads = list_upload_files(repository, package, new_latest, dir, files, :both)
    paths = MapSet.new(uploads, &elem(&1, 0))
    versions = [version, new_latest]
    uploaded = upload_new_files(uploads)
    delete_old_docs(repository, package, versions, paths, :both)

    targets =
      page_targets(repository, uploaded) ++
        deleted_page_targets(repository, package, [version])

    purge_hexdocs_cache(repository, package, versions, :both, targets)
  end

  def archive_key("hexpm", package, version),
    do: Path.join("docs", "#{package}-#{version}.tar.gz")

  def archive_key(repository, package, version),
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
        {bucket, key, {:file, source}, opts} ->
          {:ok, %{etag: etag}} = Hexpm.Store.put_file(bucket, key, source, opts)
          %{key: key, etag: etag}

        {bucket, key, data, opts} ->
          {:ok, %{etag: etag}} = Hexpm.Store.put(bucket, key, data, opts)
          %{key: key, etag: etag}
      end,
      max_concurrency: 32,
      timeout: 60_000
    )
    |> Hexpm.Utils.raise_async_stream_error()
    |> Enum.map(fn {:ok, upload} -> upload end)
  end

  # Each uploaded page set is checked through its index.html, versioned and
  # unversioned. Private docs sit behind a browser session the check cannot
  # carry, so only the public site is verified.
  defp page_targets("hexpm", uploaded) do
    for %{key: key, etag: etag} <- uploaded, Path.basename(key) == "index.html" do
      %{url: page_url(key), etag: etag}
    end
  end

  defp page_targets(_repository, _uploaded), do: []

  # `nil` stands for the unversioned pages.
  defp deleted_page_targets("hexpm", package, versions) do
    Enum.map(versions, fn
      nil -> %{url: page_url("#{package}/index.html"), etag: nil}
      version -> %{url: page_url("#{package}/#{version}/index.html"), etag: nil}
    end)
  end

  defp deleted_page_targets(_repository, _package, _versions), do: []

  defp page_url(key) do
    [package | rest] = Path.split(key)
    Hexpm.Utils.docs_html_url("hexpm", package, "/" <> Path.join(rest))
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

  defp purge_hexdocs_cache(repository, package, versions, :both, targets) do
    keys = Enum.map(versions, &versioned_cdn_key(repository, package, &1))
    purge(repository, [unversioned_cdn_key(repository, package) | keys], targets)
  end

  defp purge_hexdocs_cache(repository, package, versions, :versioned, targets) do
    purge(repository, Enum.map(versions, &versioned_cdn_key(repository, package, &1)), targets)
  end

  defp versioned_cdn_key(repository, package, version),
    do: "docspage/#{repository_cdn_key(repository)}#{package}/#{version}"

  defp unversioned_cdn_key(repository, package),
    do: "docspage/#{repository_cdn_key(repository)}#{package}"

  defp docs_config_cdn_key(repository, package),
    do: "docspage/#{repository_cdn_key(repository)}#{package}/docs_config.js"

  defp repository_cdn_key("hexpm"), do: ""
  defp repository_cdn_key(repository), do: repository <> "-"

  defp purge(repository, keys, targets \\ []) do
    service = if public?(repository), do: :fastly_hexdocs, else: :fastly_hexdocs_private
    Hexpm.CDN.purge(service, keys, verify: targets)
    :ok
  end
end
