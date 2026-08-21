defmodule Hexpm.Diff.Generator do
  import Bitwise

  alias Hexpm.Diff.{Cache, Request}
  alias Hexpm.Repository.Assets

  @max_file_size 100 * 1000
  @upload_concurrency 10
  @upload_timeout 120_000

  def generate(%Request{} = request) do
    with {:ok, from_path} <- download(request.from_release, request.from_checksum),
         {:ok, to_path} <- download(request.to_release, request.to_checksum),
         {:ok, from_dir} <- unpack(from_path, request, request.from),
         {:ok, to_dir} <- unpack(to_path, request, request.to),
         {:ok, metadata} <- generate_pieces(request, from_dir, to_dir) do
      Cache.put_metadata!(request, metadata)
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
        if Assets.file_checksum(path) == expected_checksum do
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
        Hexpm.TmpDir.ensure_accessible(path)
        {:ok, path}

      {:error, reason} ->
        {:error, {:invalid_tarball, reason}}
    end
  end

  defp generate_pieces(request, from_dir, to_dir) do
    files =
      (Hexpm.Utils.tree_regular_files(from_dir) ++ Hexpm.Utils.tree_regular_files(to_dir))
      |> Enum.uniq()
      |> Enum.sort()

    initial = %{
      total_diffs: 0,
      total_additions: 0,
      total_deletions: 0,
      files_changed: 0,
      files: []
    }

    metadata =
      files
      |> Stream.transform(0, fn file, index ->
        case build_piece(request, from_dir, to_dir, file) do
          :unchanged -> {[], index}
          {update, data} -> {[{index, update, data}], index + 1}
        end
      end)
      |> Task.async_stream(
        fn {index, update, data} ->
          try do
            Cache.put_piece!(request, index, data)
            update
          rescue
            exception -> {:piece_error, exception, __STACKTRACE__}
          end
        end,
        max_concurrency: @upload_concurrency,
        timeout: @upload_timeout
      )
      |> Enum.reduce(initial, fn
        {:ok, {:piece_error, exception, stacktrace}}, _metadata -> reraise(exception, stacktrace)
        {:ok, update}, metadata -> merge_metadata(metadata, update)
      end)

    {:ok, metadata}
  end

  defp build_piece(request, from_dir, to_dir, file) do
    from_path = Path.join(from_dir, file)
    to_path = Path.join(to_dir, file)
    from_path = if regular_file?(from_path), do: from_path, else: "/dev/null"
    to_path = if regular_file?(to_path), do: to_path, else: "/dev/null"
    same_contents? = same_contents?(from_path, to_path)

    cond do
      same_contents? and same_executable_mode?(from_path, to_path) ->
        :unchanged

      not same_contents? and (too_large?(from_path) or too_large?(to_path)) ->
        file = sanitize_utf8(file)
        {metadata_update(file, 0, 0), %{type: "too_large", file: file}}

      true ->
        case git_diff(from_path, to_path, request.ignore_whitespace) do
          nil ->
            :unchanged

          raw_diff ->
            raw_diff = sanitize_utf8(raw_diff)
            {additions, deletions} = count_changes(raw_diff)

            data = %{
              "diff" => raw_diff,
              "path_from" => sanitize_utf8(from_dir),
              "path_to" => sanitize_utf8(to_dir)
            }

            {metadata_update(sanitize_utf8(file), additions, deletions), data}
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
      {"", 0} -> nil
      {output, 1} -> output
      {output, status} -> raise "git diff exited with status #{status}: #{output}"
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

  defp metadata_update(file, additions, deletions) do
    %{
      total_diffs: 1,
      total_additions: additions,
      total_deletions: deletions,
      files_changed: 1,
      files: [file]
    }
  end

  defp merge_metadata(left, right) do
    %{
      total_diffs: left.total_diffs + right.total_diffs,
      total_additions: left.total_additions + right.total_additions,
      total_deletions: left.total_deletions + right.total_deletions,
      files_changed: left.files_changed + right.files_changed,
      files: left.files ++ right.files
    }
  end

  defp too_large?("/dev/null"), do: false
  defp too_large?(path), do: File.stat!(path).size > @max_file_size

  defp same_contents?("/dev/null", _path), do: false
  defp same_contents?(_path, "/dev/null"), do: false

  defp same_contents?(left, right) do
    left_stat = File.stat!(left)
    right_stat = File.stat!(right)

    left_stat.size == right_stat.size and
      left
      |> File.stream!(64 * 1024, [])
      |> Stream.zip(File.stream!(right, 64 * 1024, []))
      |> Enum.all?(fn {left_chunk, right_chunk} -> left_chunk == right_chunk end)
  end

  defp same_executable_mode?(left, right) do
    executable?(File.stat!(left).mode) == executable?(File.stat!(right).mode)
  end

  defp executable?(mode), do: band(mode, 0o111) != 0

  defp regular_file?(path) do
    match?({:ok, %File.Stat{type: :regular}}, File.lstat(path))
  end

  defp sanitize_utf8(content) when is_binary(content) do
    content
    |> String.chunk(:valid)
    |> Enum.map(fn chunk ->
      if String.valid?(chunk), do: chunk, else: String.duplicate("?", byte_size(chunk))
    end)
    |> Enum.join()
  end
end
