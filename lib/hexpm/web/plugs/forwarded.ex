defmodule Hexpm.Web.Plugs.Forwarded do
  import Plug.Conn
  require Logger

  def init(opts), do: opts

  def call(conn, _opts) do
    ip = get_req_header(conn, "x-forwarded-for")
    %{conn | remote_ip: ip(ip) || conn.remote_ip}
  end

  defp ip([ip | _]) do
    ip = String.split(ip, ",") |> List.last()

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
