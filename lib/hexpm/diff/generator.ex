defmodule Hexpm.Diff.Generator do
  alias Hexpm.Diff.{Request, Storage}
  alias Hexpm.Repository.Assets

  @max_file_size 1024 * 1024

  def generate(%Request{} = request) do
    with {:ok, from_path} <- download(request.from_release, request.from_checksum),
         {:ok, to_path} <- download(request.to_release, request.to_checksum),
         {:ok, from_dir} <- unpack(from_path, request, request.from),
         {:ok, to_dir} <- unpack(to_path, request, request.to),
         {:ok, metadata} <- generate_pieces(request, from_dir, to_dir) do
      Storage.put_metadata!(request, metadata)
      :ok
    end
  rescue
    exception -> {:error, {exception, __STACKTRACE__}}
  catch
    kind, reason -> {:error, {kind, reason}}
  end

  defp download(release, expected_checksum) do
    path = Hexpm.TmpDir.tmp_file("diff-tarball")

    case Hexpm.Store.get_to_file(:repo_bucket, Assets.tarball_store_key(release), path) do
      nil ->
        {:error, :tarball_not_found}

      _ ->
        if file_checksum(path) == expected_checksum do
          {:ok, path}
        else
          {:error, :checksum_mismatch}
        end
    end
  end

  defp unpack(tarball, request, version) do
    path = Hexpm.TmpDir.tmp_dir("diff-#{request.package}-#{version}")

    case :hex_tarball.unpack({:file, to_charlist(tarball)}, to_charlist(path)) do
      {:ok, _} ->
        ensure_readable(path)
        {:ok, path}

      {:error, reason} ->
        {:error, {:invalid_tarball, reason}}
    end
  end

  defp generate_pieces(request, from_dir, to_dir) do
    files = Enum.sort(Enum.uniq(tree_files(from_dir) ++ tree_files(to_dir)))

    initial =
      {%{total_diffs: 0, total_additions: 0, total_deletions: 0, files_changed: 0}, 0}

    Enum.reduce_while(files, {:ok, initial}, fn file, {:ok, {metadata, index}} ->
      case generate_piece(request, from_dir, to_dir, file, index) do
        :unchanged ->
          {:cont, {:ok, {metadata, index}}}

        {:ok, update} ->
          {:cont, {:ok, {merge_metadata(metadata, update), index + 1}}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, {metadata, _index}} -> {:ok, metadata}
      error -> error
    end
  end

  defp generate_piece(request, from_dir, to_dir, file, index) do
    from_path = Path.join(from_dir, file)
    to_path = Path.join(to_dir, file)
    from_path = if File.regular?(from_path, raw: true), do: from_path, else: "/dev/null"
    to_path = if File.regular?(to_path, raw: true), do: to_path, else: "/dev/null"

    cond do
      too_large?(from_path) or too_large?(to_path) ->
        Storage.put_piece!(request, index, %{type: "too_large", file: sanitize_utf8(file)})
        {:ok, metadata_update(0, 0)}

      true ->
        case git_diff(from_path, to_path, request.ignore_whitespace) do
          {:ok, nil} ->
            :unchanged

          {:ok, raw_diff} ->
            raw_diff = sanitize_utf8(raw_diff)

            Storage.put_piece!(request, index, %{
              "diff" => raw_diff,
              "path_from" => sanitize_utf8(from_dir),
              "path_to" => sanitize_utf8(to_dir)
            })

            {additions, deletions} = count_changes(raw_diff)
            {:ok, metadata_update(additions, deletions)}

          {:error, reason} ->
            {:error, {:git_diff, reason}}
        end
    end
  end

  defp git_diff(from_path, to_path, ignore_whitespace) do
    args =
      [
        "-c",
        "core.quotepath=false",
        "-c",
        "diff.algorithm=histogram",
        "diff",
        "--no-index",
        "--no-color"
      ] ++ if(ignore_whitespace, do: ["-w"], else: []) ++ [from_path, to_path]

    case System.cmd("git", args, stderr_to_stdout: true) do
      {"", 0} -> {:ok, nil}
      {output, 1} -> {:ok, output}
      other -> {:error, other}
    end
  end

  defp count_changes(raw_diff) do
    Enum.reduce(String.split(raw_diff, "\n"), {0, 0}, fn
      "+" <> _ = line, {additions, deletions} ->
        if String.starts_with?(line, "+++"),
          do: {additions, deletions},
          else: {additions + 1, deletions}

      "-" <> _ = line, {additions, deletions} ->
        if String.starts_with?(line, "---"),
          do: {additions, deletions},
          else: {additions, deletions + 1}

      _, counts ->
        counts
    end)
  end

  defp metadata_update(additions, deletions) do
    %{total_diffs: 1, total_additions: additions, total_deletions: deletions, files_changed: 1}
  end

  defp merge_metadata(left, right) do
    Map.new(left, fn {key, value} -> {key, value + Map.fetch!(right, key)} end)
  end

  defp too_large?("/dev/null"), do: false
  defp too_large?(path), do: File.stat!(path).size > @max_file_size

  defp tree_files(directory) do
    directory
    |> Path.join("**")
    |> Path.wildcard(match_dot: true)
    |> Enum.filter(&File.regular?(&1, raw: true))
    |> Enum.map(&Path.relative_to(&1, directory))
  end

  defp ensure_readable(dir) do
    dir
    |> Path.join("**")
    |> Path.wildcard(match_dot: true)
    |> Enum.each(fn path ->
      case File.stat(path) do
        {:ok, %{type: :directory, access: access}} when access in [:none, :write] ->
          File.chmod!(path, 0o755)

        {:ok, %{type: :regular, access: access}} when access in [:none, :write] ->
          File.chmod!(path, 0o644)

        _ ->
          :ok
      end
    end)
  end

  defp file_checksum(path) do
    path
    |> File.stream!([], 64 * 1024)
    |> Enum.reduce(:crypto.hash_init(:sha256), &:crypto.hash_update(&2, &1))
    |> :crypto.hash_final()
  end

  def sanitize_utf8(content) when is_binary(content) do
    content
    |> String.chunk(:valid)
    |> Enum.map(fn chunk ->
      if String.valid?(chunk), do: chunk, else: String.duplicate("?", byte_size(chunk))
    end)
    |> Enum.join()
  end
end
