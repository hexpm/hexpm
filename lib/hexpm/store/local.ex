defmodule Hexpm.Store.Local do
  @behaviour Hexpm.Store

  # only used during development (not safe)

  def list(region, bucket, prefix) do
    relative = Path.join([dir(), region(region), bucket(bucket)])
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

  def get(region, bucket, key, _opts) do
    path = Path.join([dir(), region(region), bucket(bucket), key])

    case File.read(path) do
      {:ok, contents} -> contents
      {:error, :enoent} -> nil
    end
  end

  def put(region, bucket, key, blob, _opts) do
    path = Path.join([dir(), region(region), bucket(bucket), key])
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, blob)
  end

  def delete(region, bucket, key) do
    [dir(), region(region), bucket(bucket), key]
    |> Path.join()
    |> File.rm()
  end

  def delete_many(region, bucket, keys) do
    Enum.each(keys, &delete(region, bucket, &1))
  end

  defp bucket(atom) when is_atom(atom) do
    Application.get_env(:hexpm, atom) || Atom.to_string(atom)
  end

  defp bucket(binary) when is_binary(binary) do
    binary
  end

  defp region(nil) do
    "us-east-1"
  end

  defp region(binary) when is_binary(binary) do
    binary
  end

  defp dir() do
    Application.get_env(:hexpm, :tmp_dir)
    |> Path.join("store")
  end
end
