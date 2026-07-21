defmodule Hexpm.Preview.Bucket do
  def tarball_key(repository, package, version) do
    repo_prefix(repository) <> "tarballs/#{package}-#{version}.tar"
  end

  def get_tarball_to_file(repository, package, version) do
    key = tarball_key(repository, package, version)
    path = Hexpm.TmpDir.tmp_file("preview-tarball")

    case Hexpm.Store.get_to_file(:repo_bucket, key, path) do
      :ok -> {:ok, path}
      nil -> :error
    end
  end

  def put_files(repository, package, version, dir, file_paths) do
    prefix = repo_prefix(repository) <> Path.join(["files", package, version]) <> "/"
    original_file_list = Hexpm.Store.list(:preview_bucket, prefix)

    file_entries =
      Enum.map(file_paths, fn filename ->
        {repo_prefix(repository) <> Path.join(["files", package, version, filename]), filename}
      end)

    file_entries
    |> Task.async_stream(
      fn {key, filename} ->
        source = Path.join(dir, filename)
        opts = put_opts(repository, package, version) ++ content_type(filename)
        Hexpm.Store.put_file(:preview_bucket, key, source, opts)
      end,
      max_concurrency: 10,
      timeout: 60_000
    )
    |> Hexpm.Utils.raise_async_stream_error()
    |> Stream.run()

    Hexpm.Store.put(
      :preview_bucket,
      file_list_key(repository, package, version),
      JSON.encode!(file_paths),
      put_opts(repository, package, version)
    )

    new_keys = Enum.map(file_entries, &elem(&1, 0))
    Hexpm.Store.delete_many(:preview_bucket, Enum.to_list(original_file_list) -- new_keys)
  end

  def delete_files(repository, package, version) do
    prefix = repo_prefix(repository) <> Path.join(["files", package, version]) <> "/"
    keys = Hexpm.Store.list(:preview_bucket, prefix)

    Hexpm.Store.delete_many(
      :preview_bucket,
      [file_list_key(repository, package, version) | Enum.to_list(keys)]
    )
  end

  def get_file_list(repository, package, version) do
    case Hexpm.Store.get(:preview_bucket, file_list_key(repository, package, version)) do
      nil -> nil
      json -> json |> JSON.decode!() |> Enum.uniq()
    end
  end

  def get_file(repository, package, version, filename) do
    Hexpm.Store.get(:preview_bucket, file_key(repository, package, version, filename))
  end

  def file_size(repository, package, version, filename) do
    Hexpm.Store.size(:preview_bucket, file_key(repository, package, version, filename))
  end

  def update_latest_version(repository, package, version) do
    Hexpm.Store.put(
      :preview_bucket,
      latest_version_key(repository, package),
      to_string(version),
      put_opts(repository, "preview/package/#{surrogate_package(repository, package)}")
    )
  end

  def get_latest_version(repository, package) do
    Hexpm.Store.get(:preview_bucket, latest_version_key(repository, package))
  end

  def delete_latest_version(repository, package) do
    Hexpm.Store.delete(:preview_bucket, latest_version_key(repository, package))
  end

  def surrogate_keys(repository, package, version) do
    base = "preview/package/#{surrogate_package(repository, package)}"
    [base, "#{base}/version/#{version}"]
  end

  defp repo_prefix("hexpm"), do: ""
  defp repo_prefix(repository), do: "repos/#{repository}/"

  defp surrogate_package("hexpm", package), do: package
  defp surrogate_package(repository, package), do: "#{repository}-#{package}"

  defp file_key(repository, package, version, filename) do
    repo_prefix(repository) <> Path.join(["files", package, version, filename])
  end

  defp file_list_key(repository, package, version) do
    repo_prefix(repository) <> Path.join("file_lists", "#{package}-#{version}.json")
  end

  defp latest_version_key(repository, package) do
    repo_prefix(repository) <> Path.join("latest_versions", package)
  end

  defp put_opts(repository, package, version) do
    put_opts(
      repository,
      "preview/package/#{surrogate_package(repository, package)}/version/#{version}"
    )
  end

  defp put_opts(repository, key) do
    [
      cache_control: cache_control(repository),
      meta: [
        {"surrogate-key", "preview #{key}"},
        {"surrogate-control", "public, max-age=604800"}
      ]
    ]
  end

  defp cache_control("hexpm"), do: "public, max-age=3600"
  defp cache_control(_repository), do: "private, max-age=3600"

  defp content_type(path) do
    case Path.extname(path) do
      "." <> extension -> [content_type: MIME.type(extension)]
      "" -> []
    end
  end
end
