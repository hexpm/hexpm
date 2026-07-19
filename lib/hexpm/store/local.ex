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

  def list_with_sizes(bucket, prefix) do
    Enum.map(list(bucket, prefix), fn key -> {key, size(bucket, key)} end)
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
  end

  def put_file(bucket, key, source_path, _opts) do
    path = safe_path!(bucket, key)
    File.mkdir_p!(Path.dirname(path))
    File.cp!(source_path, path)
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
end
