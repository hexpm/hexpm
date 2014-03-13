defmodule HexWeb.Store.Local do
  @behaviour HexWeb.Store

  import Plug.Connection

  @dir "tmp/store"

  # only used during development (not safe)

  def upload_registry(data) do
    File.mkdir_p!(@dir)
    File.write!(Path.join(@dir, "registry.ets.gz"), :zlib.gzip(data))
  end

  def registry(conn) do
    send_file(conn, 200, Path.join(@dir, "registry.ets.gz"))
  end

  def upload_tar(name, data) do
    File.mkdir_p!(@dir)
    File.write!(Path.join(@dir, name), data)
  end

  def tar(conn, name) do
    path = Path.join(@dir, name)
    if File.exists?(path) do
      send_file(conn, 200, path)
    else
      send_resp(conn, 404, "")
    end
  end
end
