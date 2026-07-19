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

    manifest_entries =
      Enum.map(file_paths, fn filename ->
        %{path: filename, size: File.stat!(Path.join(dir, filename)).size}
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

    put_manifest(package, version, manifest_entries)

    new_keys = Enum.map(file_entries, &elem(&1, 0))
    Hexpm.Store.delete_many(:preview_bucket, Enum.to_list(original_file_list) -- new_keys)
  end

  def delete_files(package, version) do
    manifest_key = manifest_key(package, version)
    legacy_manifest_key = legacy_manifest_key(package, version)
    prefix = Path.join(["files", package, version]) <> "/"
    keys = Hexpm.Store.list(:preview_bucket, prefix)

    Hexpm.Store.delete_many(
      :preview_bucket,
      [manifest_key, legacy_manifest_key | Enum.to_list(keys)]
    )
  end

  def get_manifest(package, version) do
    case Hexpm.Store.get(:preview_bucket, manifest_key(package, version)) do
      nil -> nil
      json -> json |> Jason.decode!() |> decode_manifest()
    end
  end

  def migrate_manifest(package, version) do
    if Hexpm.Store.get(:preview_bucket, manifest_key(package, version)) do
      :current
    else
      migrate_legacy_manifest(package, version)
    end
  end

  def get_file(package, version, filename) do
    Hexpm.Store.get(:preview_bucket, Path.join(["files", package, version, filename]))
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
    Hexpm.Store.delete(:preview_bucket, Path.join("latest_versions", package))
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

  defp migrate_legacy_manifest(package, version) do
    case Hexpm.Store.get(:preview_bucket, legacy_manifest_key(package, version)) do
      nil ->
        :missing

      json ->
        files = json |> Jason.decode!() |> Enum.uniq()
        prefix = Path.join(["files", package, version]) <> "/"

        sizes =
          :preview_bucket
          |> Hexpm.Store.list_with_sizes(prefix)
          |> Map.new(fn {key, size} -> {Path.relative_to(key, prefix), size} end)

        entries = Enum.map(files, &%{path: &1, size: Map.fetch!(sizes, &1)})
        put_manifest(package, version, entries)
        :migrated
    end
  end

  defp put_manifest(package, version, entries) do
    Hexpm.Store.put(
      :preview_bucket,
      manifest_key(package, version),
      Jason.encode!(%{files: entries}),
      put_opts(package, version)
    )
  end

  defp manifest_key(package, version) do
    Path.join("file_manifests", "#{package}-#{version}.json")
  end

  defp legacy_manifest_key(package, version) do
    Path.join("file_lists", "#{package}-#{version}.json")
  end

  defp decode_manifest(%{"files" => entries}) when is_list(entries) do
    entries =
      entries
      |> Enum.map(fn %{"path" => path, "size" => size}
                     when is_binary(path) and is_integer(size) and size >= 0 ->
        {path, size}
      end)
      |> Enum.uniq_by(&elem(&1, 0))

    %{files: Enum.map(entries, &elem(&1, 0)), sizes: Map.new(entries)}
  end
end
