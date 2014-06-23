defmodule HexWeb.Plugs.Forwarded do
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    # if ip = conn.req_headers["x-forwarded-for"] do
      # TODO: Plug support ?
    # end

    if proto = List.first get_req_header(conn, "x-forwarded-proto") do
      conn = %{conn | scheme: scheme(proto, conn.scheme)}
    end

    if port = List.first get_req_header(conn, "x-forwarded-port") do
      conn = %{conn | port: port(port, conn.port)}
    end

    conn
  end

  defp scheme("http", _default), do: :http
  defp scheme("https", _default), do: :https
  defp scheme(_, default), do: default

  defp port(port, default) do
    case Integer.parse(port) do
      {int, ""} -> int
      _           -> default
    end
  end
end
