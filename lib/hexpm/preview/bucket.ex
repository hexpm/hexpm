defmodule Hexpm.Preview.Bucket do
  def get_tarball_to_file(package, version) do
    key = "tarballs/#{package}-#{version}.tar"
    path = Hexpm.TmpDir.tmp_file("preview-tarball")

    case Hexpm.Store.get_to_file(:repo_bucket, key, path) do
      :ok -> {:ok, path}
      nil -> :error
    end
  end

  def put_files(package, version, dir, file_paths) do
    prefix = Path.join(["files", package, version]) <> "/"
    original_file_list = Hexpm.Store.list(:preview_bucket, prefix)

    file_entries =
      Enum.map(file_paths, fn filename ->
        {Path.join(["files", package, version, filename]), filename}
      end)

    file_entries
    |> Task.async_stream(
      fn {key, filename} ->
        source = Path.join(dir, filename)
        opts = put_opts(package, version) ++ content_type(filename)
        Hexpm.Store.put_file(:preview_bucket, key, source, opts)
      end,
      max_concurrency: 10,
      timeout: 60_000
    )
    |> Hexpm.Utils.raise_async_stream_error()
    |> Stream.run()

    file_list_key = Path.join("file_lists", "#{package}-#{version}.json")

    Hexpm.Store.put(
      :preview_bucket,
      file_list_key,
      Jason.encode!(file_paths),
      put_opts(package, version)
    )

    new_keys = Enum.map(file_entries, &elem(&1, 0))
    Hexpm.Store.delete_many(:preview_bucket, Enum.to_list(original_file_list) -- new_keys)
  end

  def delete_files(package, version) do
    file_list_key = Path.join("file_lists", "#{package}-#{version}.json")
    prefix = Path.join(["files", package, version]) <> "/"
    keys = Hexpm.Store.list(:preview_bucket, prefix)
    Hexpm.Store.delete_many(:preview_bucket, [file_list_key | Enum.to_list(keys)])
  end

  def upload_index_sitemap(sitemap) do
    upload_sitemap("sitemaps/sitemap.xml", "preview/sitemap", sitemap)
  end

  def upload_package_sitemap(package, sitemap) do
    upload_sitemap("sitemaps/#{package}.xml", "preview/package/#{package}", sitemap)
  end

  def update_latest_version(package, version) do
    Hexpm.Store.put(
      :preview_bucket,
      Path.join("latest_versions", package),
      to_string(version),
      put_opts("preview/package/#{package}")
    )
  end

  def get_latest_version(package) do
    Hexpm.Store.get(:preview_bucket, Path.join("latest_versions", package))
  end

  def delete_latest_version(package) do
    Hexpm.Store.delete_many(:preview_bucket, [
      Path.join("latest_versions", package),
      "sitemaps/#{package}.xml"
    ])
  end

  defp upload_sitemap(path, key, sitemap) do
    Hexpm.Store.put(:preview_bucket, path, sitemap, put_opts(key))
  end

  defp put_opts(package, version) do
    put_opts("preview/package/#{package}/version/#{version}")
  end

  defp put_opts(key) do
    [
      cache_control: "public, max-age=3600",
      meta: [
        {"surrogate-key", "preview #{key}"},
        {"surrogate-control", "public, max-age=604800"}
      ]
    ]
  end

  defp content_type(path) do
    case Path.extname(path) do
      "." <> extension -> [content_type: MIME.type(extension)]
      "" -> []
    end
  end
end
