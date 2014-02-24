defmodule HexWeb.Plugs.Forwarded do
  def init(opts), do: opts

  def call(Plug.Conn[] = conn, _opts) do
    # if ip = conn.req_headers["x-forwarded-for"] do
      # TODO: Plug support ?
    # end

    if proto = conn.req_headers["x-forwarded-proto"] do
      conn = conn.scheme scheme(proto, conn.scheme)
    end

    if port = conn.req_headers["x-forwarded-port"] do
      conn = conn.port port(port, conn.port)
    end

    conn
  end

  defp scheme("http", _default), do: :http
  defp scheme("https", _default), do: :https
  defp scheme(_, default), do: default

  defp port(port, default) do
    case Integer.parse(port) do
      { int, "" } -> int
      _           -> default
    end
  end
end
