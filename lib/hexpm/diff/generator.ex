defmodule Hexpm.Diff.Generator do
  import Bitwise

  alias Hexpm.Diff.{Cache, Request}
  alias Hexpm.Repository.Assets

  @max_file_size 100 * 1000
  @upload_concurrency 32
  @upload_timeout 120_000
  @c_escapes %{
    ?a => ?\a,
    ?b => ?\b,
    ?t => ?\t,
    ?n => ?\n,
    ?v => ?\v,
    ?f => ?\f,
    ?r => ?\r,
    ?" => ?",
    ?\\ => ?\\
  }

  def generate(%Request{} = request) do
    # TmpDir tracks the calling process, so the paths must be created here
    # rather than in the download tasks.
    from_path = Hexpm.TmpDir.tmp_file("diff-tarball")
    to_path = Hexpm.TmpDir.tmp_file("diff-tarball")

    [from_download, to_download] =
      Hexpm.Utils.multi_task([
        fn -> download(from_path, request.from_release, request.from_checksum) end,
        fn -> download(to_path, request.to_release, request.to_checksum) end
      ])

    with :ok <- from_download,
         :ok <- to_download,
         {:ok, from_dir} <- unpack(from_path, request, request.from),
         {:ok, to_dir} <- unpack(to_path, request, request.to) do
      changes = changes(from_dir, to_dir)

      metadata =
        if within_limits?(changes) do
          generate_pieces(request, from_dir, to_dir, changes)
        else
          %{too_large: true, files_changed: length(changes)}
        end

      Cache.put_metadata!(request, metadata)
      :ok
    end
  rescue
    exception -> {:error, {exception, __STACKTRACE__}}
  catch
    kind, reason -> {:error, {kind, reason}}
  end

  defp download(path, release, expected_checksum) do
    case Hexpm.Store.get_to_file(:repo_bucket, Assets.tarball_store_key(release), path) do
      nil ->
        {:error, :tarball_not_found}

      _ ->
        if Assets.file_checksum(path) == expected_checksum do
          :ok
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

  defp changes(from_dir, to_dir) do
    (Hexpm.Utils.tree_regular_files(from_dir) ++ Hexpm.Utils.tree_regular_files(to_dir))
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.flat_map(&change(from_dir, to_dir, &1))
  end

  defp change(from_dir, to_dir, file) do
    from_path = Path.join(from_dir, file)
    to_path = Path.join(to_dir, file)
    from_path = if regular_file?(from_path), do: from_path, else: "/dev/null"
    to_path = if regular_file?(to_path), do: to_path, else: "/dev/null"
    same_contents? = same_contents?(from_path, to_path)

    cond do
      same_contents? and same_executable_mode?(from_path, to_path) ->
        []

      not same_contents? and (too_large?(from_path) or too_large?(to_path)) ->
        [{:too_large, file}]

      true ->
        [{:diff, file, from_path, to_path}]
    end
  end

  defp within_limits?(changes) do
    max_files = Application.fetch_env!(:hexpm, :diff_max_changed_files)
    max_bytes = Application.fetch_env!(:hexpm, :diff_max_changed_bytes)

    bytes =
      Enum.reduce(changes, 0, fn
        {:too_large, _file}, bytes -> bytes
        {:diff, _file, from_path, to_path}, bytes -> bytes + size(from_path) + size(to_path)
      end)

    length(changes) <= max_files and bytes <= max_bytes
  end

  defp generate_pieces(request, from_dir, to_dir, changes) do
    initial = %{
      total_diffs: 0,
      total_additions: 0,
      total_deletions: 0,
      files_changed: 0,
      files: []
    }

    remove_undiffed_files(from_dir, changes)
    remove_undiffed_files(to_dir, changes)

    sections =
      from_dir
      |> git_diff(to_dir, request.ignore_whitespace)
      |> sections(from_dir, to_dir)

    changes
    |> Stream.transform(0, fn change, index ->
      case build_piece(from_dir, to_dir, sections, change) do
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
  end

  defp build_piece(_from_dir, _to_dir, _sections, {:too_large, file}) do
    file = sanitize_utf8(file)
    {metadata_update(file, 0, 0), %{type: "too_large", file: file}}
  end

  defp build_piece(from_dir, to_dir, sections, {:diff, file, _from_path, _to_path}) do
    case Map.fetch(sections, file) do
      :error ->
        :unchanged

      {:ok, raw_diff} ->
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

  # Git diffs both trees in one process, so the files the walk marks too large
  # and the symlinks it skips have to be gone before it runs.
  defp remove_undiffed_files(dir, changes) do
    remove_non_regular_files(dir)

    for {:too_large, file} <- changes,
        path = Path.join(dir, file),
        regular_file?(path) do
      File.rm!(path)
    end
  end

  defp remove_non_regular_files(dir) do
    Enum.each(File.ls!(dir), fn name ->
      path = Path.join(dir, name)

      case File.lstat!(path).type do
        :directory -> remove_non_regular_files(path)
        :regular -> :ok
        _other -> File.rm!(path)
      end
    end)
  end

  defp git_diff(from_dir, to_dir, ignore_whitespace) do
    args =
      [
        "-c",
        "core.quotepath=false",
        "-c",
        "diff.algorithm=histogram",
        "diff",
        "--no-index",
        "--no-color",
        "--no-renames"
      ] ++ if(ignore_whitespace, do: ["-w"], else: []) ++ [from_dir, to_dir]

    case System.cmd("git", args, stderr_to_stdout: true) do
      {"", 0} -> ""
      {output, 1} -> output
      {output, status} -> raise "git diff exited with status #{status}: #{output}"
    end
  end

  defp sections(output, from_dir, to_dir) do
    output
    |> String.split(~r/^(?=diff --git )/m, trim: true)
    |> Map.new(&{section_file!(&1, from_dir, to_dir), &1})
  end

  # A section header names the file under the old tree, the new tree, or one
  # of each, and git quotes names with unusual characters.
  defp section_file!("diff --git " <> rest, from_dir, to_dir) do
    [header | _] = :binary.split(rest, "\n")

    file =
      case header do
        "\"" <> quoted -> quoted |> unquote_c() |> strip_tree(from_dir, to_dir)
        header -> unquoted_file(header, from_dir, to_dir)
      end

    file || raise "unexpected git diff header: #{inspect(header)}"
  end

  defp section_file!(section, _from_dir, _to_dir) do
    raise "unexpected git diff output: #{inspect(binary_part(section, 0, min(byte_size(section), 200)))}"
  end

  defp strip_tree("a" <> path, from_dir, to_dir) do
    Enum.find_value([from_dir, to_dir], fn dir ->
      prefix = dir <> "/"

      if String.starts_with?(path, prefix) do
        binary_part(path, byte_size(prefix), byte_size(path) - byte_size(prefix))
      end
    end)
  end

  defp strip_tree(_path, _from_dir, _to_dir), do: nil

  defp unquoted_file(header, from_dir, to_dir) do
    dirs = [from_dir, to_dir]

    Enum.find_value(for(a <- dirs, b <- dirs, do: {"a" <> a <> "/", " b" <> b <> "/"}), fn
      {a_prefix, b_prefix} ->
        if String.starts_with?(header, a_prefix) do
          rest = binary_part(header, byte_size(a_prefix), byte_size(header) - byte_size(a_prefix))
          length = byte_size(rest) - byte_size(b_prefix)

          if length > 0 and rem(length, 2) == 0 do
            file = binary_part(rest, 0, div(length, 2))
            if rest == file <> b_prefix <> file, do: file
          end
        end
    end)
  end

  defp unquote_c(binary), do: unquote_c(binary, [])

  defp unquote_c(<<?", _rest::binary>>, acc), do: acc |> Enum.reverse() |> IO.iodata_to_binary()

  defp unquote_c(<<?\\, a, b, c, rest::binary>>, acc)
       when a in ?0..?3 and b in ?0..?7 and c in ?0..?7 do
    unquote_c(rest, [(a - ?0) * 64 + (b - ?0) * 8 + (c - ?0) | acc])
  end

  defp unquote_c(<<?\\, c, rest::binary>>, acc) do
    case Map.fetch(@c_escapes, c) do
      {:ok, byte} -> unquote_c(rest, [byte | acc])
      :error -> nil
    end
  end

  defp unquote_c(<<c, rest::binary>>, acc), do: unquote_c(rest, [c | acc])
  defp unquote_c(<<>>, _acc), do: nil

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

  defp too_large?(path), do: size(path) > @max_file_size

  defp size("/dev/null"), do: 0
  defp size(path), do: File.stat!(path).size

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
