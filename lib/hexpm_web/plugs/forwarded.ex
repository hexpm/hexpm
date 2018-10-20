defmodule HexpmWeb.Plugs.Forwarded do
  import Plug.Conn
  require Logger

  def init(opts), do: opts

  def call(conn, _opts) do
    ip = get_req_header(conn, "x-forwarded-for")
    %{conn | remote_ip: ip(ip) || conn.remote_ip}
  end

  defp ip([ip | _]) do
    # According to https://cloud.google.com/load-balancing/docs/https/#components
    ip = String.split(ip, ",") |> Enum.at(-2)

    if ip do
      ip = String.trim(ip)

      case :inet.parse_address(to_charlist(ip)) do
        {:ok, parsed_ip} ->
          parsed_ip

        {:error, _} ->
          Logger.warn("Invalid IP: #{inspect(ip)}")
          nil
      end
    end
  end

  defp ip(_), do: nil
end
