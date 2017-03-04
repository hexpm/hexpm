defmodule HexWeb.DocsTar do
  @zlib_magic 16 + 15
  @compressed_max_size 8 * 1024 * 1024
  @uncompressed_max_size 64 * 1024 * 1024

  def parse(body) do
    with {:ok, data} <- unzip(body),
         {:ok, files} <- :erl_tar.extract({:binary, data}, [:memory]),
         files = Enum.map(files, fn {path, data} -> {List.to_string(path), data} end),
         :ok <- check_version_dirs(files),
         do: {:ok, {files, body}}
  end

  defp unzip(data) when byte_size(data) > @compressed_max_size do
    {:error, "too big"}
  end

  defp unzip(data) do
    stream = :zlib.open

    try do
      :zlib.inflateInit(stream, @zlib_magic)
      # limit single uncompressed chunk size to 512kb
      :zlib.setBufSize(stream, 512 * 1024)
      uncompressed = unzip_inflate(stream, "", 0, :zlib.inflateChunk(stream, data))
      :zlib.inflateEnd(stream)
      uncompressed
    after
      :zlib.close(stream)
    end
  end

  defp unzip_inflate(_stream, _data, total, _) when total > @uncompressed_max_size do
    {:error, "too big"}
  end

  defp unzip_inflate(stream, data, total, {:more, uncompressed}) do
    total = total + byte_size(uncompressed)
    unzip_inflate(stream, [data|uncompressed], total, :zlib.inflateChunk(stream))
  end

  defp unzip_inflate(_stream, data, _total, uncompressed) do
    {:ok, IO.iodata_to_binary([data|uncompressed])}
  end

  defp check_version_dirs(files) do
    result = Enum.all?(files, fn {path, _data} ->
      first = Path.split(path) |> hd
      Version.parse(first) == :error
    end)

    if result,
      do: :ok,
    else: {:error, "directory name not allowed to match a semver version"}
  end
end
