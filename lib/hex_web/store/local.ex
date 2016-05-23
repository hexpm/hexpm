defmodule HexWeb.Store.Local do
  @behaviour HexWeb.Store

  # only used during development (not safe)

  def list(region, bucket, prefix) do
    relative = Path.join([dir(), region(region), bucket(bucket)])
    paths = Path.join(relative, "**") |> Path.wildcard
    Enum.flat_map(paths, fn path ->
      relative = Path.relative_to(path, relative)
      if String.starts_with?(relative, prefix) and File.regular?(path) do
        [relative]
      else
        []
      end
    end)
  end

  def get(region, bucket, keys, _opts) when is_list(keys) do
    Enum.map(keys, fn key ->
      path = Path.join([dir(), region(region), bucket(bucket), key])
      case File.read(path) do
        {:ok, contents} -> contents
        {:error, :enoent} -> nil
      end
    end)
  end

  def get(region, bucket, key, opts) do
    [result] = get(region, bucket, [key], opts)
    result
  end

  def put(region, bucket, objects, _opts) do
    Enum.each(objects, fn {key, blob, opts} ->
      put(region, bucket, key, blob, opts)
    end)
  end

  def put(region, bucket, key, blob, _opts) do
    path = Path.join([dir(), region(region), bucket(bucket), key])
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, blob)
  end

  def delete(region, bucket, keys, _opts) do
    Enum.each(List.wrap(keys), fn key ->
      [dir(), region(region), bucket(bucket), key]
      |> Path.join
      |> File.rm()
    end)
  end

  defp bucket(atom) when is_atom(atom),
    do: Application.get_env(:hex_web, atom) || Atom.to_string(atom)
  defp bucket(binary) when is_binary(binary),
    do: binary

  defp region(nil),
    do: "us-east-1"
  defp region(binary) when is_binary(binary),
    do: binary

  defp dir do
    Application.get_env(:hex_web, :tmp_dir)
    |> Path.join("store")
  end
end
