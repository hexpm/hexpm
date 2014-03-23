defmodule HexWeb.Store.Local do
  @behaviour HexWeb.Store

  import Plug.Connection

  # only used during development (not safe)

  def list(prefix) do
    paths = Path.join(dir, "**") |> Path.wildcard
    Enum.flat_map(paths, fn path ->
      relative = Path.relative_to(path, dir)
      if String.starts_with?(relative, prefix) and File.regular?(path) do
        [relative]
      else
        []
      end
    end)
  end

  def get(key) do
    Path.join(dir, key) |> File.read!
  end

  def put(key, blob) do
    path = Path.join(dir, key)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, blob)
  end

  def put_registry(data) do
    File.mkdir_p!(dir)
    File.write!(Path.join(dir, "registry.ets.gz"), :zlib.gzip(data))
  end

  def registry(conn) do
    send_file(conn, 200, Path.join(dir, "registry.ets.gz"))
  end

  def put_tar(name, data) do
    File.mkdir_p!(dir)
    File.write!(Path.join(dir, name), data)
  end

  def delete_tar(name) do
    File.rm!(Path.join(dir, name))
  end

  def tar(conn, name) do
    path = Path.join(dir, name)
    if File.exists?(path) do
      send_file(conn, 200, path)
    else
      send_resp(conn, 404, "")
    end
  end

  defp dir do
    Path.join(HexWeb.Config.tmp, "store")
  end
end
