defmodule Hexpm.Store.Local do
  @behaviour Hexpm.Store

  # only used during development (not safe)

  def list(bucket, prefix) do
    relative = Path.join([dir(), bucket])
    paths = Path.join(relative, "**") |> Path.wildcard()

    Enum.flat_map(paths, fn path ->
      relative = Path.relative_to(path, relative)

      if String.starts_with?(relative, prefix) and File.regular?(path) do
        [relative]
      else
        []
      end
    end)
  end

  def get(bucket, key, _opts) do
    path = Path.join([dir(), bucket, key])

    case File.read(path) do
      {:ok, contents} -> contents
      {:error, :enoent} -> nil
    end
  end

  def put(bucket, key, blob, _opts) do
    path = Path.join([dir(), bucket, key])
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, blob)
  end

  def delete(bucket, key) do
    [dir(), bucket, key]
    |> Path.join()
    |> File.rm()
  end

  def delete_many(bucket, keys) do
    Enum.each(keys, &delete(bucket, &1))
  end

  defp dir() do
    Application.get_env(:hexpm, :tmp_dir)
    |> Path.join("store")
  end
end
