defmodule HexWeb.Plugs.Forwarded do
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    if ip = List.first get_req_header(conn, "x-forwarded-for") do
      conn = %{conn | remote_ip: ip(ip, conn.remote_ip)}
    end

    if proto = List.first get_req_header(conn, "x-forwarded-proto") do
      conn = %{conn | scheme: scheme(proto, conn.scheme)}
    end

    conn
  end

  defp scheme("http", _default), do: :http
  defp scheme("https", _default), do: :https
  defp scheme(_, default), do: default

  defp ip(ip, default) do
    parts = :binary.split(ip, ".", [:global])
    parts = Enum.map(parts, &Integer.parse/1)
    valid = Enum.all?(parts, &match?({int, ""} when int in 0..255, &1))
    parts = Enum.map(parts, &elem(&1, 0))

    if length(parts) == 4 and valid do
      List.to_tuple(parts)
    else
      default
    end
  end
end
