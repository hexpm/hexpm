defmodule Hexpm.Hexdocs do
  require Logger

  alias Hexpm.Hexdocs.{Bucket, FileRewriter, PackageSitemap, Search, SourceRepo, Tar, Utils}
  alias Hexpm.Repository.{Assets, Packages, Releases, Sitemaps}

  @special_packages Application.compile_env!(:hexpm, :hexdocs_special_packages)
  @special_package_names Map.keys(@special_packages)
  @gcs_put_debounce Application.compile_env!(:hexpm, :hexdocs_gcs_put_debounce)
  @lock_timeout :timer.minutes(4)

  # ExDoc marks these `noindex`, so listing them asks a crawler to fetch a page
  # it has been told not to keep.
  @noindex_pages ~w(404.html search.html)

  defmodule StaleArchiveError do
    defexception [:key]

    @impl true
    def message(%{key: key}), do: "Hexdocs archive changed while processing: #{key}"
  end

  def upload(key) do
    {repository, package, version} = key_components!(key)
    start = System.monotonic_time(:millisecond)
    Logger.info("UPLOAD #{key}")

    version = parse_version(package, version)
    {dir, files, checksum} = download_and_unpack!(key, repository, package, version)
    FileRewriter.rewrite_files(dir, files)

    outcome =
      locked(repository, package, fn ->
        case archive_state(key, checksum) do
          :current ->
            {all_versions, retired_versions} = versions(repository, package)
            latest? = Utils.latest_version?(package, version, all_versions)
            Bucket.upload_versioned(repository, package, version, dir, files)

            if latest? do
              Bucket.upload_unversioned(repository, package, version, dir, files)
              update_package_sitemap(repository, key, package, files)
            end

            Bucket.upload_docs_config(
              repository,
              package,
              version,
              all_versions,
              retired_versions,
              dir,
              files
            )

            {:uploaded, latest?}

          :changed ->
            raise StaleArchiveError, key: key

          :missing ->
            :removed
        end
      end)

    case outcome do
      {:uploaded, latest?} ->
        if latest? do
          update_index_sitemap(repository, key)
          update_package_names_csv(repository)
        end

        elapsed = System.monotonic_time(:millisecond) - start
        Logger.info("FINISHED UPLOADING DOCS #{key} #{elapsed}ms")

      :removed ->
        Logger.info("SKIPPING UPLOAD #{key} (archive removed)")
    end

    :ok
  end

  def search(key) do
    {repository, package, version} = key_components!(key)

    if repository == "hexpm" do
      version =
        case Version.parse(version) do
          {:ok, parsed} -> parsed
          :error when package in @special_package_names -> version
        end

      {dir, files, checksum} = download_and_unpack!(key, repository, package, version)

      files_with_content =
        Enum.flat_map(files, fn path ->
          if String.starts_with?(Path.basename(path), "search_data-") do
            [{path, File.read!(Path.join(dir, path))}]
          else
            []
          end
        end)

      case Search.find_search_items(package, version, files_with_content) do
        {proglang, items} ->
          Search.delete(package, version)
          Search.index(package, version, proglang, items)

        nil ->
          Search.delete(package, version)
          Logger.info("SKIPPING SEARCH INDEX #{key} (invalid or missing search items)")
      end

      ensure_archive_current!(key, checksum)
    else
      Logger.warning("SKIPPING SEARCH INDEX #{key} (repository is not hexpm)")
    end

    :ok
  end

  def delete(key) do
    {repository, package, version} = key_components!(key)

    if package in @special_package_names do
      :ok
    else
      parsed = Version.parse!(version)

      outcome =
        locked(repository, package, fn ->
          if Releases.docs_exist?(repository, package, version) do
            :published
          else
            {all_versions, _retired_versions} = Releases.docs_versions(repository, package)
            delete_docs(repository, package, parsed, all_versions)
            update_index_sitemap(repository, key)
            :deleted
          end
        end)

      case outcome do
        :published ->
          upload(key)

        :deleted ->
          if repository == "hexpm", do: Search.delete(package, parsed)
          :ok
      end
    end
  end

  defp delete_docs(repository, package, version, all_versions) do
    latest? = Utils.latest_version?(package, version, all_versions)
    new_latest = if latest?, do: Utils.latest_version(all_versions -- [version])

    cond do
      new_latest ->
        key = Bucket.archive_key(repository, package, new_latest)
        {dir, files, checksum} = download_and_unpack!(key, repository, package, new_latest)
        FileRewriter.rewrite_files(dir, files)
        Bucket.promote(repository, package, version, new_latest, dir, files)
        ensure_archive_current!(key, checksum)

      latest? ->
        Bucket.delete(repository, package, version, :both)

      true ->
        Bucket.delete(repository, package, version, :versioned)
    end
  end

  def sitemap(key) do
    {repository, package, version} = key_components!(key)
    {_dir, files, _checksum} = download_and_unpack!(key, repository, package, version)
    update_index_sitemap(repository, key)

    locked(repository, package, fn ->
      {all_versions, _retired_versions} = versions(repository, package)

      if Utils.latest_version?(package, parse_version(package, version), all_versions) do
        update_package_sitemap(repository, key, package, files)
      else
        Logger.info("SKIPPING PACKAGE SITEMAP #{key} (not the latest version)")
      end
    end)

    :ok
  end

  def key_components(key) do
    case Path.split(key) do
      ["repos", repository, "docs", file] -> release_components(repository, file)
      ["docs", file] -> release_components("hexpm", file)
      _other -> :error
    end
  end

  defp key_components!(key) do
    case key_components(key) do
      {:ok, repository, package, version} -> {repository, package, version}
      :error -> raise ArgumentError, "invalid Hexdocs object key: #{inspect(key)}"
    end
  end

  defp release_components(repository, file) do
    if String.ends_with?(file, ".tar.gz") do
      case String.split(Path.basename(file, ".tar.gz"), "-", parts: 2) do
        [package, version] when package != "" and version != "" ->
          {:ok, repository, package, version}

        _other ->
          :error
      end
    else
      :error
    end
  end

  defp parse_version(package, version) when package in @special_package_names do
    case Version.parse(version) do
      {:ok, parsed} -> parsed
      :error -> version
    end
  end

  defp parse_version(_package, version), do: Version.parse!(version)

  defp versions(_repository, package) when package in @special_package_names do
    {SourceRepo.versions!(Map.fetch!(@special_packages, package)), MapSet.new()}
  end

  defp versions(repository, package), do: Releases.docs_versions(repository, package)

  # Uploads and deletions of one package's docs write the same objects, and
  # which version is the latest, and whether the archive a job unpacked is
  # still the one in the store, is decided under the lock, so the last
  # writer is the version that is the latest at that moment and a job never
  # writes from an archive that has been replaced or removed. The download
  # and unpack and the site-wide files stay outside it. A failure after some
  # of the writes still has to purge what was written, so the transaction
  # commits their purge jobs before the error goes on.
  defp locked(repository, package, fun) do
    {:ok, result} =
      Hexpm.Repo.transaction(
        fn ->
          Hexpm.Repo.advisory_xact_lock(:hexdocs,
            sub_key: :erlang.phash2({repository, package}),
            timeout: @lock_timeout
          )

          try do
            {:ok, fun.()}
          catch
            kind, reason -> {:raised, kind, reason, __STACKTRACE__}
          end
        end,
        timeout: @lock_timeout
      )

    case result do
      {:ok, value} -> value
      {:raised, kind, reason, stacktrace} -> :erlang.raise(kind, reason, stacktrace)
    end
  end

  defp download_and_unpack!(key, repository, package, version) do
    path = Hexpm.TmpDir.tmp_file("docs-tarball")

    case Hexpm.Store.get_to_file(:repo_bucket, key, path) do
      :ok ->
        {dir, files} =
          Tar.unpack_to_dir!({:file, path},
            repository: repository,
            package: package,
            version: version
          )

        {dir, files, Assets.file_checksum(path)}

      nil ->
        raise "Hexdocs archive not found in store: #{key}"
    end
  end

  defp ensure_archive_current!(key, checksum) do
    if archive_state(key, checksum) == :current do
      :ok
    else
      raise StaleArchiveError, key: key
    end
  end

  defp archive_state(key, checksum) do
    path = Hexpm.TmpDir.tmp_file("docs-tarball")

    case Hexpm.Store.get_to_file(:repo_bucket, key, path) do
      :ok -> if Assets.file_checksum(path) == checksum, do: :current, else: :changed
      nil -> :missing
    end
  end

  defp update_index_sitemap("hexpm", key) do
    Logger.info("UPDATING INDEX SITEMAP #{key}")

    Hexpm.Hexdocs.Debouncer.debounce(
      Hexpm.Hexdocs.Debouncer,
      :sitemap_index,
      @gcs_put_debounce,
      fn ->
        Bucket.upload_index_sitemap(fn ->
          Sitemaps.render_docs(Sitemaps.packages_with_docs())
        end)
      end
    )
  end

  defp update_index_sitemap(_repository, _key), do: :ok

  defp update_package_sitemap("hexpm", _key, package, files) do
    pages =
      for path <- files,
          Path.extname(path) == ".html",
          path not in @noindex_pages,
          do: path

    Bucket.upload_package_sitemap(package, fn ->
      PackageSitemap.render(package, pages, DateTime.utc_now())
    end)
  end

  defp update_package_sitemap(_repository, _key, _package, _files), do: :ok

  defp update_package_names_csv("hexpm") do
    Bucket.upload_package_names_csv(fn ->
      names = Enum.sort(@special_package_names) ++ Packages.public_names()
      for name <- names, do: [name, "\n"]
    end)
  end

  defp update_package_names_csv(_repository), do: :ok
end
