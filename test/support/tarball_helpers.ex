defmodule Hexpm.TarballHelpers do
  @moduledoc false

  # `:hex_tarball.create` rejects symlinks, but tarballs published by old Hex
  # clients contain them, so rebuild contents.tar.gz with the links added and
  # recompute both checksums.
  def add_symlinks(tarball, symlinks) do
    root = Hexpm.TmpDir.tmp_dir("tarball-symlinks")
    {:ok, outer} = :erl_tar.extract({:binary, tarball}, [:memory])
    outer = Map.new(outer, fn {name, binary} -> {List.to_string(name), binary} end)
    version = Map.fetch!(outer, "VERSION")
    metadata_binary = Map.fetch!(outer, "metadata.config")

    contents_dir = Path.join(root, "contents")
    File.mkdir_p!(contents_dir)

    :ok =
      :erl_tar.extract({:binary, Map.fetch!(outer, "contents.tar.gz")}, [
        :compressed,
        {:cwd, to_charlist(contents_dir)}
      ])

    for {relative, target} <- symlinks do
      path = Path.join(contents_dir, relative)
      File.mkdir_p!(Path.dirname(path))
      File.ln_s!(target, path)
    end

    entries =
      for relative <- tree_entries(contents_dir, ""),
          do: {to_charlist(relative), to_charlist(Path.join(contents_dir, relative))}

    contents_path = Path.join(root, "contents.tar.gz")
    :ok = :erl_tar.create(to_charlist(contents_path), entries, [:compressed])
    contents = File.read!(contents_path)
    inner_checksum = :crypto.hash(:sha256, [version, metadata_binary, contents])

    outer_path = Path.join(root, "outer.tar")

    :ok =
      :erl_tar.create(
        to_charlist(outer_path),
        [
          {~c"VERSION", version},
          {~c"CHECKSUM", Base.encode16(inner_checksum)},
          {~c"metadata.config", metadata_binary},
          {~c"contents.tar.gz", contents}
        ],
        []
      )

    new_tarball = File.read!(outer_path)

    %{
      tarball: new_tarball,
      inner_checksum: inner_checksum,
      outer_checksum: :crypto.hash(:sha256, new_tarball)
    }
  end

  defp tree_entries(root, relative) do
    full = if relative == "", do: root, else: Path.join(root, relative)

    Enum.flat_map(File.ls!(full), fn name ->
      entry = if relative == "", do: name, else: relative <> "/" <> name

      case File.lstat!(Path.join(root, entry)).type do
        :directory -> tree_entries(root, entry)
        _file_or_link -> [entry]
      end
    end)
  end
end
