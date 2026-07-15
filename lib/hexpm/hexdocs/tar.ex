defmodule Hexpm.Hexdocs.Tar do
  require Logger

  defmodule UnpackError do
    defexception [:repository, :package, :version, :reason]

    @impl true
    def message(error) do
      "Failed to unpack #{error.repository}/#{error.package} #{error.version}: #{error.reason}"
    end
  end

  def unpack_to_dir!({:file, path}, opts \\ []) do
    repository = Keyword.get(opts, :repository, "UNKNOWN")
    package = Keyword.get(opts, :package, "UNKNOWN")
    version = Keyword.get(opts, :version, "UNKNOWN")
    output_dir = Hexpm.TmpDir.tmp_dir("docs")

    case :hex_tarball.unpack_docs({:file, to_charlist(path)}, to_charlist(output_dir)) do
      :ok ->
        ensure_readable(output_dir)

        files =
          output_dir
          |> Path.join("**")
          |> Path.wildcard(match_dot: true)
          |> Enum.filter(&File.regular?(&1, raw: true))
          |> Enum.map(&Path.relative_to(&1, output_dir))
          |> fix_paths(repository, package, version)

        check_version_dirs!(repository, package, version, files)
        {output_dir, files}

      {:error, reason} ->
        raise UnpackError,
          repository: repository,
          package: package,
          version: version,
          reason: inspect(reason)
    end
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

        _ ->
          :ok
      end
    end)
  end

  defp check_version_dirs!(repository, package, version, files) do
    unless Enum.all?(files, &(Version.parse(hd(Path.split(&1))) == :error)) do
      raise UnpackError,
        repository: repository,
        package: package,
        version: version,
        reason: "root file or directory name not allowed to match a semver version"
    end
  end

  defp fix_paths(files, repository, package, version) do
    Enum.flat_map(files, fn path ->
      case Path.safe_relative(path) do
        {:ok, path} when path != "" ->
          [path]

        :error ->
          Logger.error("Unsafe path from #{repository}/#{package} #{version}: #{path}")
          []
      end
    end)
  end
end
