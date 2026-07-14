defmodule Hexpm.Preview do
  require Logger

  alias Hexpm.Preview.{Bucket, Data, Sitemaps}

  def upload(key) do
    {package, version} = key_components!(key)
    start = System.monotonic_time(:millisecond)
    Logger.info("UPLOAD #{key}")

    if Data.release_exists?(package, version) do
      {dir, file_paths, checksum} = download_and_unpack!(package, version)
      Bucket.put_files(package, version, dir, file_paths)

      reconcile_uploaded_release(package, version, file_paths, checksum)
    else
      delete_contents(package, version)
    end

    purge(package, version)
    elapsed = System.monotonic_time(:millisecond) - start
    Logger.info("FINISHED UPLOADING PREVIEW #{key} #{elapsed}ms")
    :ok
  end

  def delete(key) do
    {package, version} = key_components!(key)
    start = System.monotonic_time(:millisecond)
    Logger.info("DELETE #{key}")

    if Data.release_exists?(package, version) do
      upload(key)
    else
      delete_contents(package, version)
      purge(package, version)
    end

    elapsed = System.monotonic_time(:millisecond) - start
    Logger.info("FINISHED DELETING PREVIEW #{key} #{elapsed}ms")
    :ok
  end

  def sitemap(key) do
    {package, version} = key_components!(key)
    {_dir, file_paths, checksum} = download_and_unpack!(package, version)
    update_package_sitemap(package, file_paths)
    ensure_tarball_current!(package, version, checksum)
    :ok
  end

  def key_components(key) do
    case Path.split(key) do
      ["tarballs", file] -> release_components(file)
      _other -> :error
    end
  end

  defp release_components(file) do
    if String.ends_with?(file, ".tar") do
      case String.split(Path.basename(file, ".tar"), "-", parts: 2) do
        [package, version] when package != "" and version != "" -> {:ok, package, version}
        _other -> :error
      end
    else
      :error
    end
  end

  defp key_components!(key) do
    case key_components(key) do
      {:ok, package, version} -> {package, version}
      :error -> raise ArgumentError, "invalid Preview object key: #{inspect(key)}"
    end
  end

  defp download_and_unpack!(package, version) do
    case Bucket.get_tarball_to_file(package, version) do
      {:ok, tarball_path} ->
        output_dir = Hexpm.TmpDir.tmp_dir("preview-package")

        case :hex_tarball.unpack({:file, to_charlist(tarball_path)}, to_charlist(output_dir)) do
          {:ok, _metadata} ->
            ensure_readable(output_dir)

            {
              output_dir,
              file_paths(output_dir, package, version),
              file_checksum(tarball_path)
            }

          {:error, reason} ->
            raise "Failed to unpack Preview tarball #{package} #{version}: #{inspect(reason)}"
        end

      :error ->
        raise "Preview tarball not found in store: tarballs/#{package}-#{version}.tar"
    end
  end

  defp file_paths(output_dir, package, version) do
    output_dir
    |> Path.join("**")
    |> Path.wildcard(match_dot: true)
    |> Enum.filter(&File.regular?(&1, raw: true))
    |> Enum.flat_map(fn full_path ->
      relative = Path.relative_to(full_path, output_dir)

      if relative == "hex_metadata.config" do
        []
      else
        case safe_path(Path.split(relative), []) do
          {:ok, path} ->
            [Path.join(path)]

          :error ->
            Logger.error("Unsafe path from #{package} #{version}: #{relative}")
            []
        end
      end
    end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp ensure_readable(dir) do
    dir
    |> Path.join("**")
    |> Path.wildcard(match_dot: true)
    |> Enum.each(fn path ->
      case File.stat(path) do
        {:ok, %{type: :directory, access: access}} when access in [:none, :write] ->
          File.chmod(path, 0o755)

        {:ok, %{type: :regular, access: access}} when access in [:none, :write] ->
          File.chmod(path, 0o644)

        _other ->
          :ok
      end
    end)
  end

  defp latest_version?(package, version) do
    case Data.latest_version(package) do
      nil -> false
      latest -> Version.compare(latest, version) == :eq
    end
  end

  defp delete_contents(package, version) do
    Bucket.delete_files(package, version)

    if Bucket.get_latest_version(package) == version do
      reconcile_latest(package)
    end

    update_index_sitemap()

    if Data.release_exists?(package, version) do
      upload("tarballs/#{package}-#{version}.tar")
    end
  end

  defp reconcile_uploaded_release(package, version, file_paths, checksum) do
    cond do
      not Data.release_exists?(package, version) ->
        delete_contents(package, version)

      not tarball_current?(package, version, checksum) ->
        raise "Preview tarball changed while processing: tarballs/#{package}-#{version}.tar"

      latest_version?(package, version) ->
        Bucket.update_latest_version(package, version)
        update_package_sitemap(package, file_paths)
        update_index_sitemap()
        reconcile_latest_after_publish(package, version, checksum)

      true ->
        :ok
    end
  end

  defp reconcile_latest_after_publish(package, version, checksum) do
    cond do
      not Data.release_exists?(package, version) ->
        delete_contents(package, version)

      not tarball_current?(package, version, checksum) ->
        raise "Preview tarball changed while processing: tarballs/#{package}-#{version}.tar"

      not latest_version?(package, version) ->
        reconcile_latest(package)

      true ->
        :ok
    end
  end

  defp reconcile_latest(package) do
    case Data.latest_version(package) do
      nil ->
        Bucket.delete_latest_version(package)

      latest ->
        latest = to_string(latest)
        {dir, file_paths, checksum} = download_and_unpack!(package, latest)
        Bucket.put_files(package, latest, dir, file_paths)

        cond do
          not Data.release_exists?(package, latest) ->
            Bucket.delete_files(package, latest)
            reconcile_latest(package)

          not tarball_current?(package, latest, checksum) ->
            raise "Preview tarball changed while processing: tarballs/#{package}-#{latest}.tar"

          not latest_version?(package, latest) ->
            reconcile_latest(package)

          true ->
            Bucket.update_latest_version(package, latest)
            update_package_sitemap(package, file_paths)
            purge(package, latest)
            reconcile_latest_after_publish(package, latest, checksum)
        end
    end
  end

  defp ensure_tarball_current!(package, version, checksum) do
    unless tarball_current?(package, version, checksum) do
      raise "Preview tarball changed while processing: tarballs/#{package}-#{version}.tar"
    end
  end

  defp tarball_current?(package, version, checksum) do
    case Bucket.get_tarball_to_file(package, version) do
      {:ok, path} -> file_checksum(path) == checksum
      :error -> false
    end
  end

  defp file_checksum(path) do
    hash =
      path
      |> File.stream!([], 64 * 1024)
      |> Enum.reduce(:crypto.hash_init(:sha256), &:crypto.hash_update(&2, &1))

    :crypto.hash_final(hash)
  end

  defp update_index_sitemap do
    preview_url = Application.fetch_env!(:hexpm, :preview_url)
    Bucket.upload_index_sitemap(Sitemaps.render_index(preview_url, Data.packages()))
  end

  defp update_package_sitemap(package, file_paths) do
    preview_url = Application.fetch_env!(:hexpm, :preview_url)

    Bucket.upload_package_sitemap(
      package,
      Sitemaps.render_package(preview_url, package, file_paths, DateTime.utc_now())
    )
  end

  defp purge(package, version) do
    Hexpm.CDN.purge_key(:fastly_hexrepo, [
      "preview/sitemap",
      "preview/package/#{package}",
      "preview/package/#{package}/version/#{version}"
    ])
  end

  defp safe_path(["." | rest], acc), do: safe_path(rest, acc)
  defp safe_path([".." | rest], [_previous | acc]), do: safe_path(rest, acc)
  defp safe_path([".." | _rest], []), do: :error
  defp safe_path([path | rest], acc), do: safe_path(rest, [path | acc])
  defp safe_path([], []), do: :error
  defp safe_path([], acc), do: {:ok, Enum.reverse(acc)}
end
