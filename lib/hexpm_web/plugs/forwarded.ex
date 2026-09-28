defmodule HexpmWeb.Plugs.Forwarded do
  import Plug.Conn
  require Logger

  # The load balancer sets this header on every request it forwards and
  # overwrites any value the client sent:
  # https://cloud.google.com/load-balancing/docs/https/custom-headers
  @secret_header "x-hexpm-load-balancer-secret"

  def init(opts), do: opts

  def call(conn, _opts) do
    remote_ip = remote_ip(conn, Application.get_env(:hexpm, :load_balancer_secret))

    conn
    |> delete_req_header(@secret_header)
    |> Map.put(:remote_ip, remote_ip)
  end

  def remote_ip(conn, secret) do
    if load_balancer?(get_req_header(conn, @secret_header), secret) do
      forwarded_ip(conn.remote_ip, get_req_header(conn, "x-forwarded-for"))
    else
      conn.remote_ip
    end
  end

  defp load_balancer?([value], secret) when is_binary(secret) and secret != "" do
    Plug.Crypto.secure_compare(value, secret)
  end

  defp load_balancer?(_values, _secret), do: false

  # https://cloud.google.com/load-balancing/docs/https#x-forwarded-for_header
  defp forwarded_ip(peer, headers) do
    ip =
      headers
      |> Enum.join(",")
      |> String.split(",")
      |> Enum.at(-2)

    if ip do
      ip = String.trim(ip)

      case :inet.parse_address(to_charlist(ip)) do
        {:ok, parsed_ip} ->
          parsed_ip

        {:error, _} ->
          Logger.warning("Invalid IP: #{inspect(ip)}")
          peer
      end
    else
      peer
    end
  end
end
