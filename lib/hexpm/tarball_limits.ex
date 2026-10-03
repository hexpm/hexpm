defmodule Hexpm.TarballLimits do
  @moduledoc """
  Checks the entries of uploaded package and docs tarballs before anything is
  extracted to disk.

  A tarball may have at most 10,000 entries, each path at most 255 bytes
  and 16 segments deep. Docs tarballs may contain only regular files and
  directories, package contents may also contain symlinks. The outer package
  tarball may contain only regular files at its root.

  The headers are read the way `:hex_erl_tar` reads them: PAX and GNU long
  name headers override the entry name, symlinks, hard links and directories
  carry no data, and concatenated gzip members are read as one stream.
  Anything this parser can't read is rejected. The sum of the entry sizes is
  capped at the uncompressed size limit `:hex_tarball` applies, which bounds
  how much is inflated.
  """

  import Bitwise

  @max_entries 10_000
  @max_path_bytes 255
  @max_depth 16
  @max_compressed_size 16 * 1024 * 1024
  @max_uncompressed_size 128 * 1024 * 1024
  @max_extended_header_size 1024 * 1024
  @max_extended_headers 4

  @block_size 512
  @zero_block <<0::size(@block_size * 8)>>

  @type error() ::
          :too_many_entries
          | :too_big
          | {:path_too_long, binary()}
          | {:path_too_deep, binary()}
          | {:unsupported_type, binary(), atom()}
          | {:unexpected_file, binary()}
          | {:invalid, atom()}

  @doc """
  Checks the outer tarball of a package, which is not compressed.
  """
  @spec check_package_outer(Path.t()) :: :ok | {:error, error()}
  def check_package_outer(path) do
    with {:ok, _contents} <- package_outer(path), do: :ok
  end

  @doc """
  Checks the outer tarball of a package and its `contents.tar.gz`.
  """
  @spec check_package(Path.t()) :: :ok | {:error, error()}
  def check_package(path) do
    case package_outer(path) do
      {:ok, nil} -> :ok
      {:ok, contents} -> scan(gzip_source(contents), [:regular, :directory, :symlink], nil)
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Checks a gzipped docs tarball.
  """
  @spec check_docs(Path.t()) :: :ok | {:error, error()}
  def check_docs(path) do
    if too_big_to_check?(path) do
      :ok
    else
      scan(gzip_source(File.read!(path)), [:regular, :directory], nil)
    end
  end

  @spec format_error(error()) :: String.t()
  def format_error(:too_many_entries), do: "tarball has more than #{@max_entries} files"

  def format_error(:too_big) do
    List.to_string(
      :hex_tarball.format_error({:tarball, {:too_big_uncompressed, @max_uncompressed_size}})
    )
  end

  def format_error({:path_too_long, name}),
    do: "path in tarball is longer than #{@max_path_bytes} bytes: #{printable(name)}"

  def format_error({:path_too_deep, name}),
    do: "path in tarball is nested deeper than #{@max_depth} levels: #{printable(name)}"

  def format_error({:unsupported_type, name, type}),
    do: "unsupported file type in tarball: #{printable(name)} (#{type})"

  def format_error({:unexpected_file, name}),
    do: "unexpected file in tarball: #{printable(name)}"

  def format_error({:invalid, :bad_header}), do: "invalid tarball: bad header"
  def format_error({:invalid, :eof}), do: "invalid tarball: unexpected end of file"

  def format_error({:invalid, :invalid_end_of_archive}),
    do: "invalid tarball: invalid end of archive"

  def format_error({:invalid, :bad_extended_header}),
    do: "invalid tarball: bad extended header"

  def format_error({:invalid, :bad_gzip}), do: "invalid tarball: bad gzip compression"

  defp printable(name) do
    name =
      if byte_size(name) > @max_path_bytes, do: binary_part(name, 0, @max_path_bytes), else: name

    if String.valid?(name), do: name, else: inspect(name)
  end

  # `:hex_tarball` rejects inputs over the compressed size limit before it
  # extracts anything, so those are left to it and its error message.
  defp too_big_to_check?(path) do
    File.stat!(path).size > @max_compressed_size
  end

  defp package_outer(path) do
    if too_big_to_check?(path) do
      {:ok, nil}
    else
      scan(binary_source(File.read!(path)), [:regular], "contents.tar.gz")
    end
  end

  defp binary_source(binary), do: %{buffer: binary, source: :done}

  defp gzip_source(binary), do: %{buffer: <<>>, source: {:gzip, binary}}

  # With `capture` set the tarball is an outer package tarball: every entry
  # must be a regular file at the root, and the data of the last entry named
  # `capture` is returned, matching which file the extraction keeps.
  defp scan(reader, types, capture) do
    state = %{
      types: types,
      capture: capture,
      captured: nil,
      entries: 0,
      total_size: 0,
      extended: %{},
      extended_count: 0
    }

    reader = open(reader)

    try do
      state = scan_entries(reader, state)
      if capture, do: {:ok, state.captured}, else: :ok
    catch
      {:tarball_limits, reason} -> {:error, reason}
    after
      close(reader)
    end
  end

  defp scan_entries(reader, state) do
    case read_block(reader) do
      {:eof, _reader} ->
        state

      {@zero_block, reader} ->
        case read(reader, @block_size) do
          {<<>>, _reader} -> state
          {@zero_block, _reader} -> state
          {block, _reader} when byte_size(block) < @block_size -> fail({:invalid, :eof})
          {_block, _reader} -> fail({:invalid, :invalid_end_of_archive})
        end

      {block, reader} ->
        header = parse_header(block)
        {reader, state} = handle_header(header, reader, state)
        scan_entries(reader, state)
    end
  end

  defp handle_header(%{typeflag: typeflag} = header, reader, state)
       when typeflag in [?x, ?L, ?K] do
    if header.size > @max_extended_header_size,
      do: fail({:invalid, :bad_extended_header})

    state = add_size(state, header.size)
    state = %{state | extended_count: state.extended_count + 1}

    if state.extended_count > @max_extended_headers,
      do: fail({:invalid, :bad_extended_header})

    {data, reader} = read_data(reader, header.size)

    extended =
      case typeflag do
        ?x -> parse_pax(data, state.extended)
        ?L -> Map.put(state.extended, "path", parse_string(data))
        ?K -> Map.put(state.extended, "linkpath", parse_string(data))
      end

    {reader, %{state | extended: extended}}
  end

  defp handle_header(header, reader, state) do
    entries = state.entries + 1
    if entries > @max_entries, do: fail(:too_many_entries)

    name = Map.get(state.extended, "path", header.name)
    type = type(header.typeflag)
    segments = segments(name)

    unless type in state.types, do: fail({:unsupported_type, name, type})
    if byte_size(name) > @max_path_bytes, do: fail({:path_too_long, name})
    if length(segments) > @max_depth, do: fail({:path_too_deep, name})

    if state.capture && (length(segments) != 1 or hd(segments) == ".."),
      do: fail({:unexpected_file, name})

    state = add_size(state, header.size)
    state = %{state | entries: entries, extended: %{}, extended_count: 0}

    if state.capture && segments == [state.capture] do
      {data, reader} = read_data(reader, header.size)
      {reader, %{state | captured: data}}
    else
      {skip_data(reader, header.size), state}
    end
  end

  defp add_size(state, size) do
    total_size = state.total_size + size
    if total_size > @max_uncompressed_size, do: fail(:too_big)
    %{state | total_size: total_size}
  end

  defp segments(name) do
    name
    |> :binary.split("/", [:global])
    |> Enum.reject(&(&1 in ["", "."]))
  end

  defp type(typeflag) when typeflag in [?0, 0], do: :regular
  defp type(?1), do: :link
  defp type(?2), do: :symlink
  defp type(?3), do: :char
  defp type(?4), do: :block
  defp type(?5), do: :directory
  defp type(?6), do: :fifo
  defp type(?7), do: :contiguous
  defp type(?S), do: :sparse
  defp type(?g), do: :global_header
  defp type(_typeflag), do: :unknown

  defp parse_header(block) do
    <<name::binary-100, _mode::binary-8, _uid::binary-8, _gid::binary-8, size::binary-12,
      _mtime::binary-12, checksum::binary-8, typeflag, _linkname::binary-100, magic::binary-6,
      _version::binary-2, _::binary-80, prefix::binary-155, _::binary-8, trailer::binary-4>> =
      block

    verify_checksum(block, parse_octal(checksum))

    prefix =
      cond do
        magic == "ustar\0" and trailer == "tar\0" -> parse_string(binary_part(prefix, 0, 131))
        magic == "ustar\0" -> parse_string(prefix)
        true -> ""
      end

    name = parse_string(name)
    name = if prefix == "", do: name, else: prefix <> "/" <> name
    size = if typeflag in [?1, ?2, ?5], do: 0, else: parse_numeric(size)

    %{name: name, typeflag: typeflag, size: size}
  end

  defp verify_checksum(block, expected) do
    <<before::binary-148, _checksum::binary-8, rest::binary>> = block
    unsigned = sum(before, :unsigned) + 8 * ?\s + sum(rest, :unsigned)
    signed = sum(before, :signed) + 8 * ?\s + sum(rest, :signed)
    unless expected in [unsigned, signed], do: fail({:invalid, :bad_header})
  end

  defp sum(binary, :unsigned), do: for(<<byte <- binary>>, reduce: 0, do: (acc -> acc + byte))

  defp sum(binary, :signed),
    do: for(<<byte::signed <- binary>>, reduce: 0, do: (acc -> acc + byte))

  defp parse_numeric(<<first, _::binary>> = binary) when (first &&& 0x80) != 0 do
    if (first &&& 0x40) != 0, do: fail({:invalid, :bad_header})
    bits = bit_size(binary) - 1
    <<_::1, value::size(^bits)>> = binary
    if value >= 1 <<< 63, do: fail({:invalid, :bad_header})
    value
  end

  defp parse_numeric(binary), do: parse_octal(binary)

  defp parse_octal(binary) do
    for <<char <- binary>>, char not in [?\s, 0], reduce: 0 do
      acc when char in ?0..?7 -> acc * 8 + (char - ?0)
      _acc -> fail({:invalid, :bad_header})
    end
  end

  defp parse_string(binary) do
    case :binary.split(binary, <<0>>) do
      [string | _] -> string
    end
  end

  defp parse_pax(<<>>, extended), do: extended

  defp parse_pax(data, extended) do
    with [record, rest] <- :binary.split(data, "\n"),
         [_length, record] <- :binary.split(record, " ", [:trim_all]),
         [key, value] <- :binary.split(record, "=", [:trim_all]) do
      parse_pax(rest, Map.put(extended, key, value))
    else
      _ -> fail({:invalid, :bad_extended_header})
    end
  end

  defp fail(reason), do: throw({:tarball_limits, reason})

  defp padding(size), do: rem(@block_size - rem(size, @block_size), @block_size)

  defp read_block(reader) do
    case read(reader, @block_size) do
      {<<>>, reader} -> {:eof, reader}
      {block, _reader} when byte_size(block) < @block_size -> fail({:invalid, :eof})
      {block, reader} -> {block, reader}
    end
  end

  defp read_data(reader, size) do
    {data, reader} = read(reader, size)
    if byte_size(data) < size, do: fail({:invalid, :eof})
    {data, skip_data(reader, 0, padding(size))}
  end

  defp skip_data(reader, size), do: skip_data(reader, size, padding(size))

  defp skip_data(reader, size, padding) do
    case skip(reader, size + padding) do
      {0, reader} -> reader
      {_missing, _reader} -> fail({:invalid, :eof})
    end
  end

  # Returns up to `size` bytes, fewer only at the end of the stream.
  defp read(%{buffer: buffer} = reader, size) when byte_size(buffer) >= size do
    <<data::binary-size(^size), rest::binary>> = buffer
    {data, %{reader | buffer: rest}}
  end

  defp read(reader, size) do
    case fill(reader) do
      {:ok, reader} -> read(reader, size)
      {:eof, reader} -> {reader.buffer, %{reader | buffer: <<>>}}
    end
  end

  # Returns how many of the `size` bytes were missing at the end of the stream.
  defp skip(%{buffer: buffer} = reader, size) when byte_size(buffer) >= size do
    <<_::binary-size(^size), rest::binary>> = buffer
    {0, %{reader | buffer: rest}}
  end

  defp skip(%{buffer: buffer} = reader, size) do
    reader = %{reader | buffer: <<>>}
    size = size - byte_size(buffer)

    case fill(reader) do
      {:ok, reader} -> skip(reader, size)
      {:eof, reader} -> {size, reader}
    end
  end

  defp open(%{source: {:gzip, binary}} = reader) do
    z = :zlib.open()
    :ok = :zlib.inflateInit(z, 31, :reset)
    %{reader | source: {:inflating, z, binary}}
  end

  defp open(reader), do: reader

  defp fill(%{source: :done} = reader), do: {:eof, reader}

  defp fill(%{source: {:inflating, z, input}} = reader) do
    case :zlib.safeInflate(z, input) do
      {:continue, output} ->
        buffer = reader.buffer <> IO.iodata_to_binary(output)
        {:ok, %{reader | buffer: buffer, source: {:inflating, z, []}}}

      {:finished, output} ->
        :zlib.inflateEnd(z)
        buffer = reader.buffer <> IO.iodata_to_binary(output)
        {:ok, %{reader | buffer: buffer, source: {:finished, z}}}
    end
  rescue
    ErlangError -> fail({:invalid, :bad_gzip})
  end

  defp fill(%{source: {:finished, _z}} = reader), do: {:eof, reader}

  defp close(%{source: {:inflating, z, _input}}), do: :zlib.close(z)
  defp close(_reader), do: :ok
end
