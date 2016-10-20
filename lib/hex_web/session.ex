defmodule HexWeb.Session do
  @behaviour Plug

  def init(opts), do: Plug.Session.init(opts)

  def call(conn, opts) do
    case Map.fetch(conn.private, :plug_session_fetch) do
      {:ok, :bypass} ->
        Plug.Conn.put_private(conn, :plug_session_fetch, :done)
      :error ->
        Plug.Session.call(conn, opts)
    end
  end
end
