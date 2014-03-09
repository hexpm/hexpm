defmodule HexWeb.Store.Local do
  @behaviour HexWeb.Store

  import Plug.Connection

  @dir "tmp/store"
  @registry_file "tmp/store/registry.ets"

  def upload_registry(file) do
    File.mkdir_p!(@dir)
    File.cp!(file, @registry_file)
  end

  def registry(conn) do
    send_file(conn, 200, @registry_file)
  end
end
