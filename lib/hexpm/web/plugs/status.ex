defmodule HexpmWeb.Plugs.Status do
  import Plug.Conn
  alias Plug.Conn

  def init(opts), do: opts

  def call(%Conn{path_info: ["status"]} = conn, _opts) do
    conn
    |> send_resp(200, "")
    |> halt()
  end

  def call(conn, _opts) do
    conn
  end
end
