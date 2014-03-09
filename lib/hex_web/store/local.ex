defmodule HexWeb.Store.Local do
  @behaviour HexWeb.Store

  import Plug.Connection

  @dir "tmp/store"
  @registry_file "tmp/store/registry.ets.gz"

  def upload_registry(file) do
    File.mkdir_p!(@dir)

    data = File.read!(file)
    File.write!(@registry_file, :zlib.gzip(data))
  end

  def registry(conn) do
    send_file(conn, 200, @registry_file)
  end
end
