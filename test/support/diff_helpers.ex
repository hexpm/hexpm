defmodule Hexpm.DiffHelpers do
  def insert_tarball_release(package, version, files) do
    root = Hexpm.TmpDir.tmp_dir("diff-fixture")

    tarball_files =
      Enum.map(files, fn {relative, value} ->
        {content, mode} = normalize_file(value)
        path = Path.join(root, relative)
        File.mkdir_p!(Path.dirname(path))
        File.write!(path, content)
        File.chmod!(path, mode)
        {to_charlist(relative), to_charlist(path)}
      end)

    metadata = %{
      "name" => package.name,
      "version" => "0.0.0",
      "description" => "Diff fixture",
      "licenses" => ["MIT"],
      "files" => Map.keys(files),
      "requirements" => %{},
      "app" => package.name,
      "build_tools" => ["mix"]
    }

    {:ok, result} = :hex_tarball.create(metadata, tarball_files)

    release =
      Hexpm.Factory.insert(:release,
        package: package,
        version: version,
        inner_checksum: result.inner_checksum,
        outer_checksum: result.outer_checksum
      )

    Hexpm.Store.put(
      :repo_bucket,
      "tarballs/#{package.name}-#{version}.tar",
      result.tarball,
      []
    )

    release
  end

  def cache_object(key), do: Hexpm.Store.get(:diff_bucket, key)

  defp normalize_file({content, mode}), do: {content, mode}
  defp normalize_file(content), do: {content, 0o644}
end
