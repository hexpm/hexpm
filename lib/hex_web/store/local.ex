defmodule HexWeb.Store.Local do
  @behaviour HexWeb.Store

  import Plug.Conn

  # only used during development (not safe)

  def list_logs(_, _, prefix) do
    relative = Path.join(dir, "logs")
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

  def get_logs(_, _, key) do
    Path.join("logs", key) |> get
  end

  def put_logs(_, _, key, blob) do
    Path.join("logs", key) |> put(blob)
  end

  def put_registry(data, _signature) do
    File.mkdir_p!(dir)
    File.write!(Path.join(dir, "registry.ets.gz"), data)
  end

  def put_registry_signature(signature) do
    File.mkdir_p!(dir)
    File.write!(Path.join(dir, "registry.ets.gz.signed"), signature)
  end

  def send_registry(conn) do
    conn =
      case File.read(Path.join(dir, "registry.ets.gz.signed")) do
        {:ok, contents} -> put_resp_header(conn, "x-hex-signature", contents)
        _               -> conn
      end
    send_file(conn, 200, Path.join(dir, "registry.ets.gz"))
  end

  def send_registry_signature(conn) do
    send_file(conn, 200, Path.join(dir, "registry.ets.gz.signed"))
  end

  def put_release(package, version, data) do
    name = "#{package}-#{version}.tar"
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

  def put_docs(name, data) do
    path = Path.join("docs", name)
    put(path, data)
  end

  def delete_docs(name) do
    path = Path.join("docs", name)
    delete(path)
  end

  def send_docs(conn, name) do
    path = Path.join("docs", name)
    send_file(conn, path)
  end

  def put_docs_file(path, data) do
    path = Path.join("docs_pages", path)
    put(path, data)
  end

  def put_docs_page(path, _key, data) do
    path = Path.join("docs_pages", path)
    put(path, data)
  end

  def list_docs_pages(path) do
    paths = Path.join([dir, "docs_pages", path, "**"])
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

  def delete_docs_page(path) do
    path = Path.join("docs_pages", path)
    delete(path)
  end

  def send_docs_page(conn, path) do
    path = Path.join("docs_pages", path)
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

  defp get(key) do
    Path.join(dir, key) |> File.read!
  end

  defp put(key, blob) do
    path = Path.join(dir, key)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, blob)
  end

  defp delete(key) do
    File.rm(Path.join(dir, key))
  end

  defp dir do
    Application.get_env(:hex_web, :tmp_dir)
    |> Path.join("store")
  end
end
