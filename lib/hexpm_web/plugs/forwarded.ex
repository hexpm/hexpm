defmodule HexpmWeb.Plugs.Forwarded do
  import Plug.Conn
  require Logger

  def init(opts), do: opts

  def call(conn, _opts) do
    remote_ip = remote_ip(conn.remote_ip, get_req_header(conn, "x-forwarded-for"))
    %{conn | remote_ip: remote_ip}
  end

  def remote_ip(default, [forwarded_for | _]) do
    # According to https://cloud.google.com/load-balancing/docs/https/#components
    ip = String.split(forwarded_for, ",") |> Enum.at(-2)

    if ip do
      ip = String.trim(ip)

      case :inet.parse_address(to_charlist(ip)) do
        {:ok, parsed_ip} ->
          parsed_ip

        {:error, _} ->
          Logger.warning("Invalid IP: #{inspect(ip)}")
          default
      end
    else
      default
    end
  end

  def remote_ip(default, _headers), do: default
end
