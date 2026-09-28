defmodule HexpmWeb.Plugs.Forwarded do
  import Bitwise
  import Plug.Conn
  require Logger

  # https://cloud.google.com/load-balancing/docs/firewall-rules
  @load_balancer_ranges [
    {{130, 211, 0, 0}, 22},
    {{35, 191, 0, 0}, 16}
  ]

  def init(opts), do: opts

  def call(conn, _opts) do
    remote_ip = remote_ip(conn.remote_ip, get_req_header(conn, "x-forwarded-for"))
    %{conn | remote_ip: remote_ip}
  end

  def remote_ip(peer, headers) do
    if load_balancer?(peer) do
      forwarded_ip(peer, headers)
    else
      peer
    end
  end

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

  defp load_balancer?(ip) do
    case ipv4(ip) do
      {:ok, ip} ->
        ip = ipv4_to_integer(ip)

        Enum.any?(@load_balancer_ranges, fn {network, prefix} ->
          mask = bnot((1 <<< (32 - prefix)) - 1) &&& 0xFFFFFFFF
          (ip &&& mask) == ipv4_to_integer(network)
        end)

      :error ->
        false
    end
  end

  defp ipv4({_, _, _, _} = ip), do: {:ok, ip}

  defp ipv4({0, 0, 0, 0, 0, 0xFFFF, high, low}),
    do: {:ok, {high >>> 8, high &&& 0xFF, low >>> 8, low &&& 0xFF}}

  defp ipv4(_ip), do: :error

  defp ipv4_to_integer({a, b, c, d}), do: a <<< 24 ||| b <<< 16 ||| c <<< 8 ||| d
end
