defmodule Hexpm.Preview do
  require Logger

  alias Hexpm.Preview.{Bucket, Sitemaps}
  alias Hexpm.Repository.Releases
  alias Hexpm.Repository.Sitemaps, as: RepositorySitemaps

  @max_file_size 2 * 1000 * 1000
  @readme_filenames ~w(README.md readme.md README.markdown readme.markdown README.txt readme.txt README readme)

  def source(package, version, requested_filename \\ nil) do
    with [_ | _] = files <- Bucket.get_file_list(package, version),
         filename <- selected_file(files, requested_filename),
         size when is_integer(size) <- Bucket.file_size(package, version, filename),
         result when is_map(result) <- source_result(package, version, filename, size) do
      {:ok, Map.merge(result, %{files: files, filename: filename})}
    else
      _ -> :error
    end
  end

  def readme(package, version) do
    with files when is_list(files) <- Bucket.get_file_list(package, version),
         filename when is_binary(filename) <- Enum.find(@readme_filenames, &(&1 in files)),
         contents when is_binary(contents) <- Bucket.get_file(package, version, filename) do
      {:ok, filename, contents}
    else
      _ -> :error
    end
  end

  def get_latest_version(package), do: Bucket.get_latest_version(package)

  defp default_file(files) do
    Enum.min_by(files, &default_file_priority/1)
  end

  def index_sitemap(base_url) do
    Sitemaps.render_index(base_url, RepositorySitemaps.public_packages())
  end

  def package_sitemap(base_url, package) do
    with %DateTime{} = updated_at <- RepositorySitemaps.public_package_updated_at(package),
         version when is_binary(version) <- Bucket.get_latest_version(package),
         [_ | _] = files <- Bucket.get_file_list(package, version) do
      {:ok, Sitemaps.render_package(base_url, package, files, updated_at)}
    else
      _ -> :error
    end
  end

  def upload(key) do
    {package, version} = key_components!(key)
    start = System.monotonic_time(:millisecond)
    Logger.info("UPLOAD #{key}")

    if release_exists?(package, version) do
      {dir, file_paths, checksum} = download_and_unpack!(package, version)
      Bucket.put_files(package, version, dir, file_paths)

      reconcile_uploaded_release(package, version, checksum)
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

    if release_exists?(package, version) do
      upload(key)
    else
      delete_contents(package, version)
      purge(package, version)
    end

    elapsed = System.monotonic_time(:millisecond) - start
    Logger.info("FINISHED DELETING PREVIEW #{key} #{elapsed}ms")
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
        case Path.safe_relative(relative) do
          {:ok, path} when path != "" ->
            [path]

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
    case latest_version(package) do
      nil -> false
      latest -> Version.compare(latest, version) == :eq
    end
  end

  defp delete_contents(package, version) do
    Bucket.delete_files(package, version)

    if Bucket.get_latest_version(package) == version do
      reconcile_latest(package)
    end

    if release_exists?(package, version) do
      upload("tarballs/#{package}-#{version}.tar")
    end
  end

  defp reconcile_uploaded_release(package, version, checksum) do
    cond do
      not release_exists?(package, version) ->
        delete_contents(package, version)

      not tarball_current?(package, version, checksum) ->
        raise "Preview tarball changed while processing: tarballs/#{package}-#{version}.tar"

      latest_version?(package, version) ->
        Bucket.update_latest_version(package, version)
        reconcile_latest_after_publish(package, version, checksum)

      true ->
        :ok
    end
  end

  defp reconcile_latest_after_publish(package, version, checksum) do
    cond do
      not release_exists?(package, version) ->
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
    case latest_version(package) do
      nil ->
        Bucket.delete_latest_version(package)

      latest ->
        latest = to_string(latest)
        {dir, file_paths, checksum} = download_and_unpack!(package, latest)
        Bucket.put_files(package, latest, dir, file_paths)

        cond do
          not release_exists?(package, latest) ->
            Bucket.delete_files(package, latest)
            reconcile_latest(package)

          not tarball_current?(package, latest, checksum) ->
            raise "Preview tarball changed while processing: tarballs/#{package}-#{latest}.tar"

          not latest_version?(package, latest) ->
            reconcile_latest(package)

          true ->
            Bucket.update_latest_version(package, latest)
            purge(package, latest)
            reconcile_latest_after_publish(package, latest, checksum)
        end
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

  defp purge(package, version) do
    Hexpm.CDN.purge_key(:fastly_hexrepo, [
      "preview/package/#{package}",
      "preview/package/#{package}/version/#{version}"
    ])
  end

  defp release_exists?(package, version) do
    Releases.exists?("hexpm", package, version)
  end

  defp latest_version(package) do
    Releases.latest_version("hexpm", package,
      only_stable: true,
      unstable_fallback: true
    )
  end

  defp selected_file(files, requested_filename) do
    if requested_filename in files, do: requested_filename, else: default_file(files)
  end

  defp source_result(_package, _version, _filename, size) when size > @max_file_size do
    %{contents: nil, type: {:too_large, size}}
  end

  defp source_result(package, version, filename, _size) do
    case Bucket.get_file(package, version, filename) do
      nil -> :error
      contents when is_binary(contents) -> source_contents(contents)
    end
  end

  defp source_contents(contents) do
    if String.valid?(contents) do
      %{contents: contents, type: :text}
    else
      %{contents: nil, type: :binary}
    end
  end

  @default_file_priority ["mix.exs", "rebar.config", "Makefile"]
                         |> Enum.with_index(2)
                         |> Map.new()

  defp default_file_priority(file) do
    if file |> String.downcase() |> String.starts_with?("readme") do
      1
    else
      Map.get(@default_file_priority, file, 1000)
    end
  end
end
