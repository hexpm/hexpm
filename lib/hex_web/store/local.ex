defmodule HexWeb.Store.Local do
  @behaviour HexWeb.Store

  import Plug.Conn

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

  def send_registry(conn) do
    send_file(conn, 200, Path.join(dir, "registry.ets.gz"))
  end

  def put_release(name, data) do
    path = Path.join("tarballs", name)
    put(path, data)
  end

  def delete_release(name) do
    path = Path.join("tarballs", name)
    delete(path)
  end

  def send_release(conn, name) do
    path = Path.join("tarballs", name)
    send_file(conn, path)
  end

  def put_docs(package, version, data) do
    path = Path.join("docs", "#{package}-#{version}.tar.gz")
    put(path, data)
  end

  def delete_docs(package, version) do
    path = Path.join("docs", "#{package}-#{version}.tar.gz")
    delete(path)
  end

  def send_docs(conn, package, version) do
    path = Path.join("docs", "#{package}-#{version}.tar.gz")
    send_file(conn, path)
  end

  def put_docs_page(package, version, file, data) do
    path = Path.join(["docs_pages", package, version, file])
    put(path, data)
  end

  def list_docs_pages(package, version) do
    paths = Path.join([dir, "docs_pages", package, version, "**"])
            |> Path.wildcard

    relative = Path.join(dir, "docs_pages")
    Enum.flat_map(paths, fn path ->
      relative = Path.relative_to(path, relative)
      if File.regular?(path) do
        [relative]
      else
        []
      end
    end)
  end

  def delete_docs_page(package, version, file) do
    path = Path.join(["docs_pages", package, version, file])
    delete(path)
  end

  def send_docs_page(conn, package, version, file) do
    path = Path.join(["docs_pages", package, version, file])
    send_file(conn, path)
  end

  defp send_file(conn, name) do
    path = Path.join(dir, name)
    if File.exists?(path) do
      send_file(conn, 200, path)
    else
      send_resp(conn, 404, "")
    end
  end

  defp delete(key) do
    File.rm!(Path.join(dir, key))
  end

  defp dir do
    Path.join(Application.get_env(:hex_web, :tmp), "store")
  end
end
