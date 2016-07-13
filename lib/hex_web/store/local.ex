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

  def get(region, bucket, key, _opts) do
    path = Path.join([dir(), region(region), bucket(bucket), key])
    case File.read(path) do
      {:ok, contents} -> contents
      {:error, :enoent} -> nil
    end
  end

  def get_many(region, bucket, keys, opts) do
    Enum.map(keys, &get(region, bucket, &1, opts))
  end

  def get_each(region, bucket, keys, fun, opts) do
    get_many(region, bucket, keys, opts)
    |> Enum.zip(keys)
    |> Enum.each(fn {body, key} -> fun.(key, body) end)
  end

  def get_reduce(region, bucket, keys, acc, fun, opts) do
    get_many(region, bucket, keys, opts)
    |> Enum.zip(keys)
    |> Enum.reduce(acc, fn {body, key}, acc -> fun.(key, body, acc) end)
  end

  def put(region, bucket, key, blob, _opts) do
    path = Path.join([dir(), region(region), bucket(bucket), key])
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, blob)
  end

  def put_many(region, bucket, objects, _opts) do
    Enum.each(objects, fn {key, blob, opts} ->
      put(region, bucket, key, blob, opts)
    end)
  end

  def put_multipart_init(_region, _bucket, _key, _opts) do
    raise "not implemented"
  end

  def put_multipart_part(_region, _bucket, _key, _upload_id, _part_number, _blob) do
    raise "not implemented"
  end

  def put_multipart_complete(_region, _bucket, _key, _upload_id, _parts) do
    raise "not implemented"
  end

  def delete(region, bucket, key, _opts) do
    [dir(), region(region), bucket(bucket), key]
    |> Path.join
    |> File.rm
  end

  def delete_many(region, bucket, keys, opts) do
    Enum.each(keys, &delete(region, bucket, &1, opts))
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
