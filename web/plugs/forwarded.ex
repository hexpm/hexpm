defmodule HexWeb.Plugs.Forwarded do
  import Plug.Conn
  require Logger

  def init(opts), do: opts

  def call(conn, _opts) do
    ip = get_req_header(conn, "x-forwarded-for")
    %{conn | remote_ip: ip(ip) || conn.remote_ip}
  end

  defp ip([ip|_]) do
    ip = :binary.split(ip, ",", [:global]) |> List.last

    if ip do
      ip    = String.strip(ip)
      parts = :binary.split(ip, ".", [:global])
      parts = Enum.map(parts, &Integer.parse/1)
      valid = Enum.all?(parts, &match?({int, ""} when int in 0..255, &1))

      if length(parts) == 4 and valid do
        parts = Enum.map(parts, &elem(&1, 0))
        List.to_tuple(parts)
      else
        Logger.warn("Invalid IP: #{inspect ip}")
        nil
      end
    end
  end

  defp ip(_), do: nil
end
