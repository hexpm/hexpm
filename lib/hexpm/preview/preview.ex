defmodule Hexpm.Preview do
  require Logger

  alias Hexpm.Preview.{Bucket, Sitemaps}
  alias Hexpm.Repository.{Assets, Releases}
  alias Hexpm.Repository.Sitemaps, as: RepositorySitemaps

  @max_file_size 100 * 1000
  @readme_filenames ~w(README.md readme.md README.markdown readme.markdown README.txt readme.txt README readme)

  def source(repository, package, version, requested_filename \\ nil) do
    with [_ | _] = files <- Bucket.get_file_list(repository, package, version),
         filename when is_binary(filename) <- selected_file(files, requested_filename),
         size when is_integer(size) <- Bucket.file_size(repository, package, version, filename),
         result when is_map(result) <-
           source_result(repository, package, version, filename, size) do
      {:ok, Map.merge(result, %{files: files, filename: filename})}
    else
      _ -> :error
    end
  end

  def readme(repository, package, version) do
    with files when is_list(files) <- Bucket.get_file_list(repository, package, version),
         filename when is_binary(filename) <- Enum.find(@readme_filenames, &(&1 in files)),
         contents when is_binary(contents) <-
           Bucket.get_file(repository, package, version, filename) do
      {:ok, filename, contents}
    else
      _ -> :error
    end
  end

  def raw_file(repository, package, version, filename) do
    with files when is_list(files) <- Bucket.get_file_list(repository, package, version),
         true <- filename in files,
         contents when is_binary(contents) <-
           Bucket.get_file(repository, package, version, filename) do
      {:ok, contents}
    else
      _ -> :error
    end
  end

  def get_latest_version(repository, package), do: Bucket.get_latest_version(repository, package)

  defp default_file(files) do
    Enum.min_by(files, &default_file_priority/1)
  end

  def index_sitemap(base_url) do
    Sitemaps.render_index(base_url, RepositorySitemaps.public_packages())
  end

  def package_sitemap(base_url, package) do
    with %DateTime{} = updated_at <- RepositorySitemaps.public_package_updated_at(package),
         version when is_binary(version) <- Bucket.get_latest_version("hexpm", package),
         [_ | _] = files <- Bucket.get_file_list("hexpm", package, version) do
      {:ok, Sitemaps.render_package(base_url, package, version, files, updated_at)}
    else
      _ -> :error
    end
  end

  def upload(key) do
    {repository, package, version} = key_components!(key)
    start = System.monotonic_time(:millisecond)
    Logger.info("UPLOAD #{key}")

    if release_exists?(repository, package, version) do
      {dir, file_paths, checksum} = download_and_unpack!(repository, package, version)
      Bucket.put_files(repository, package, version, dir, file_paths)

      reconcile_uploaded_release(repository, package, version, checksum)
    else
      delete_contents(repository, package, version)
    end

    purge(repository, package, version)
    elapsed = System.monotonic_time(:millisecond) - start
    Logger.info("FINISHED UPLOADING PREVIEW #{key} #{elapsed}ms")
    :ok
  end

  def delete(key) do
    {repository, package, version} = key_components!(key)
    start = System.monotonic_time(:millisecond)
    Logger.info("DELETE #{key}")

    if release_exists?(repository, package, version) do
      upload(key)
    else
      delete_contents(repository, package, version)
      purge(repository, package, version)
    end

    elapsed = System.monotonic_time(:millisecond) - start
    Logger.info("FINISHED DELETING PREVIEW #{key} #{elapsed}ms")
    :ok
  end

  def key_components(key) do
    case Path.split(key) do
      ["tarballs", file] ->
        release_components("hexpm", file)

      ["repos", repository, "tarballs", file] when repository != "" ->
        release_components(repository, file)

      _other ->
        :error
    end
  end

  defp release_components(repository, file) do
    if String.ends_with?(file, ".tar") do
      case String.split(Path.basename(file, ".tar"), "-", parts: 2) do
        [package, version] when package != "" and version != "" ->
          {:ok, repository, package, version}

        _other ->
          :error
      end
    else
      :error
    end
  end

  defp key_components!(key) do
    case key_components(key) do
      {:ok, repository, package, version} -> {repository, package, version}
      :error -> raise ArgumentError, "invalid Preview object key: #{inspect(key)}"
    end
  end

  defp download_and_unpack!(repository, package, version) do
    case Bucket.get_tarball_to_file(repository, package, version) do
      {:ok, tarball_path} ->
        output_dir = Hexpm.TmpDir.tmp_dir("preview-package")

        case :hex_tarball.unpack({:file, to_charlist(tarball_path)}, to_charlist(output_dir)) do
          {:ok, _metadata} ->
            Hexpm.TmpDir.ensure_accessible(output_dir)

            {
              output_dir,
              file_paths(output_dir, repository, package, version),
              Assets.file_checksum(tarball_path)
            }

          {:error, reason} ->
            raise "Failed to unpack Preview tarball #{repository} #{package} #{version}: #{inspect(reason)}"
        end

      :error ->
        raise "Preview tarball not found in store: #{Bucket.tarball_key(repository, package, version)}"
    end
  end

  defp file_paths(output_dir, repository, package, version) do
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
            Logger.error("Unsafe path from #{repository} #{package} #{version}: #{relative}")
            []
        end
      end
    end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp latest_version?(repository, package, version) do
    case latest_version(repository, package) do
      nil -> false
      latest -> Version.compare(latest, version) == :eq
    end
  end

  defp delete_contents(repository, package, version) do
    Bucket.delete_files(repository, package, version)

    if Bucket.get_latest_version(repository, package) == version do
      reconcile_latest(repository, package)
    end

    if release_exists?(repository, package, version) do
      upload(Bucket.tarball_key(repository, package, version))
    end
  end

  defp reconcile_uploaded_release(repository, package, version, checksum) do
    cond do
      not release_exists?(repository, package, version) ->
        delete_contents(repository, package, version)

      not tarball_current?(repository, package, version, checksum) ->
        raise "Preview tarball changed while processing: #{Bucket.tarball_key(repository, package, version)}"

      latest_version?(repository, package, version) ->
        Bucket.update_latest_version(repository, package, version)
        reconcile_latest_after_publish(repository, package, version, checksum)

      true ->
        :ok
    end
  end

  defp reconcile_latest_after_publish(repository, package, version, checksum) do
    cond do
      not release_exists?(repository, package, version) ->
        delete_contents(repository, package, version)

      not tarball_current?(repository, package, version, checksum) ->
        raise "Preview tarball changed while processing: #{Bucket.tarball_key(repository, package, version)}"

      not latest_version?(repository, package, version) ->
        reconcile_latest(repository, package)

      true ->
        :ok
    end
  end

  defp reconcile_latest(repository, package) do
    case latest_version(repository, package) do
      nil ->
        Bucket.delete_latest_version(repository, package)

      latest ->
        latest = to_string(latest)
        {dir, file_paths, checksum} = download_and_unpack!(repository, package, latest)
        Bucket.put_files(repository, package, latest, dir, file_paths)

        cond do
          not release_exists?(repository, package, latest) ->
            Bucket.delete_files(repository, package, latest)
            reconcile_latest(repository, package)

          not tarball_current?(repository, package, latest, checksum) ->
            raise "Preview tarball changed while processing: #{Bucket.tarball_key(repository, package, latest)}"

          not latest_version?(repository, package, latest) ->
            reconcile_latest(repository, package)

          true ->
            Bucket.update_latest_version(repository, package, latest)
            purge(repository, package, latest)
            reconcile_latest_after_publish(repository, package, latest, checksum)
        end
    end
  end

  defp tarball_current?(repository, package, version, checksum) do
    case Bucket.get_tarball_to_file(repository, package, version) do
      {:ok, path} -> Assets.file_checksum(path) == checksum
      :error -> false
    end
  end

  defp purge(repository, package, version) do
    Hexpm.CDN.purge_key(:fastly_hexrepo, Bucket.surrogate_keys(repository, package, version))
  end

  defp release_exists?(repository, package, version) do
    Releases.exists?(repository, package, version)
  end

  defp latest_version(repository, package) do
    Releases.latest_version(repository, package,
      only_stable: true,
      unstable_fallback: true
    )
  end

  defp selected_file(files, nil), do: default_file(files)

  defp selected_file(files, requested_filename) do
    if requested_filename in files, do: requested_filename
  end

  defp source_result(_repository, _package, _version, _filename, size)
       when size > @max_file_size do
    %{contents: nil, type: {:too_large, size}}
  end

  defp source_result(repository, package, version, filename, _size) do
    case Bucket.get_file(repository, package, version, filename) do
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
