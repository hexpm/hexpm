defmodule Hexpm.Hexdocs do
  require Logger

  alias Hexpm.Hexdocs.{Bucket, FileRewriter, PackageSitemap, Search, SourceRepo, Tar, Utils}
  alias Hexpm.Repository.{Packages, Releases, Sitemaps}

  @special_packages Application.compile_env!(:hexpm, :hexdocs_special_packages)
  @special_package_names Map.keys(@special_packages)
  @gcs_put_debounce Application.compile_env!(:hexpm, :hexdocs_gcs_put_debounce)

  def upload(key) do
    {repository, package, version} = key_components!(key)
    start = System.monotonic_time(:millisecond)
    Logger.info("UPLOAD #{key}")

    {version, all_versions, retired_versions} = versions(repository, package, version)
    {dir, files} = download_and_unpack!(key, repository, package, version)
    FileRewriter.rewrite_files(dir, files)
    Bucket.upload(repository, package, version, all_versions, retired_versions, dir, files)

    if Utils.latest_version?(package, version, all_versions) do
      update_index_sitemap(repository, key)
      update_package_sitemap(repository, key, package, files)
      update_package_names_csv(repository)
    end

    elapsed = System.monotonic_time(:millisecond) - start
    Logger.info("FINISHED UPLOADING DOCS #{key} #{elapsed}ms")
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

      {dir, files} = download_and_unpack!(key, repository, package, version)

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
      version = Version.parse!(version)
      {all_versions, _retired_versions} = Releases.docs_versions(repository, package)
      Bucket.delete(repository, package, version, all_versions)
      update_index_sitemap(repository, key)
      if repository == "hexpm", do: Search.delete(package, version)
      :ok
    end
  end

  def sitemap(key) do
    {repository, package, version} = key_components!(key)
    {_dir, files} = download_and_unpack!(key, repository, package, version)
    update_index_sitemap(repository, key)
    update_package_sitemap(repository, key, package, files)
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

  defp versions(_repository, package, version) when package in @special_package_names do
    version =
      case Version.parse(version) do
        {:ok, parsed} -> parsed
        :error -> version
      end

    {version, SourceRepo.versions!(Map.fetch!(@special_packages, package)), MapSet.new()}
  end

  defp versions(repository, package, version) do
    {all_versions, retired_versions} = Releases.docs_versions(repository, package)
    {Version.parse!(version), all_versions, retired_versions}
  end

  defp download_and_unpack!(key, repository, package, version) do
    path = Hexpm.TmpDir.tmp_file("docs-tarball")

    case Hexpm.Store.get_to_file(:repo_bucket, key, path) do
      :ok ->
        Tar.unpack_to_dir!({:file, path},
          repository: repository,
          package: package,
          version: version
        )

      nil ->
        raise "Hexdocs archive not found in store: #{key}"
    end
  end

  defp update_index_sitemap("hexpm", key) do
    Logger.info("UPDATING INDEX SITEMAP #{key}")

    Hexpm.Hexdocs.Debouncer.debounce(
      Hexpm.Hexdocs.Debouncer,
      :sitemap_index,
      @gcs_put_debounce,
      fn -> Bucket.upload_index_sitemap(Sitemaps.render_docs(Sitemaps.packages_with_docs())) end
    )
  end

  defp update_index_sitemap(_repository, _key), do: :ok

  defp update_package_sitemap("hexpm", _key, package, files) do
    pages = for path <- files, Path.extname(path) == ".html", do: path

    Bucket.upload_package_sitemap(
      package,
      PackageSitemap.render(package, pages, DateTime.utc_now())
    )
  end

  defp update_package_sitemap(_repository, _key, _package, _files), do: :ok

  defp update_package_names_csv("hexpm") do
    names = Enum.sort(@special_package_names) ++ Packages.public_names()
    Bucket.upload_package_names_csv(for name <- names, do: [name, "\n"])
  end

  defp update_package_names_csv(_repository), do: :ok
end
