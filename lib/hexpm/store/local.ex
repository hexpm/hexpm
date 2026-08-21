defmodule Hexpm.Store.Local do
  @behaviour Hexpm.Store.Behaviour

  # only used during development (not safe)

  def list(bucket, prefix) do
    bucket_dir = Path.join([dir(), bucket])
    paths = Path.join(bucket_dir, "**") |> Path.wildcard()

    Enum.flat_map(paths, fn path ->
      relative = Path.relative_to(path, bucket_dir)

      if String.starts_with?(relative, prefix) and File.regular?(path) do
        [relative]
      else
        []
      end
    end)
  end

  def get(bucket, key, _opts) do
    path = safe_path!(bucket, key)

    case File.read(path) do
      {:ok, contents} -> contents
      {:error, :enoent} -> nil
    end
  end

  def size(bucket, key) do
    path = safe_path!(bucket, key)

    case File.stat(path) do
      {:ok, stat} -> stat.size
      {:error, :enoent} -> nil
    end
  end

  def get_to_file(bucket, key, destination, _opts) do
    path = safe_path!(bucket, key)

    if File.regular?(path) do
      File.cp!(path, destination)
      :ok
    end
  end

  def put(bucket, key, blob, _opts) do
    path = safe_path!(bucket, key)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, blob)
    {:ok, %{etag: quote_etag(:crypto.hash(:md5, blob))}}
  end

  def put_file(bucket, key, source_path, _opts) do
    path = safe_path!(bucket, key)
    File.mkdir_p!(Path.dirname(path))
    File.cp!(source_path, path)

    hash =
      path
      |> File.stream!(65_536)
      |> Enum.reduce(:crypto.hash_init(:md5), &:crypto.hash_update(&2, &1))
      |> :crypto.hash_final()

    {:ok, %{etag: quote_etag(hash)}}
  end

  def delete(bucket, key) do
    bucket
    |> safe_path!(key)
    |> File.rm()
  end

  def delete_many(bucket, keys) do
    Enum.each(keys, &delete(bucket, &1))
  end

  defp safe_path!(bucket, key) do
    bucket_dir = Path.join([dir(), bucket])

    case Path.safe_relative(key, bucket_dir) do
      {:ok, relative} -> Path.join(bucket_dir, relative)
      :error -> raise ArgumentError, "invalid path"
    end
  end

  defp dir() do
    Application.get_env(:hexpm, :local_store_dir) ||
      Path.join(Application.fetch_env!(:hexpm, :tmp_dir), "store")
  end

  defp quote_etag(hash), do: ~s("#{Base.encode16(hash, case: :lower)}")
end
