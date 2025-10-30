defmodule HexpmWeb.RequestHelpers do
  @moduledoc """
  Shared helpers for extracting and parsing request information
  like IP addresses and user agents.
  """

  @doc """
  Builds a usage info map from a Phoenix connection.
  Returns a map with ip, used_at, and user_agent fields.
  """
  def build_usage_info(conn) do
    %{
      ip: parse_ip(conn.remote_ip),
      used_at: DateTime.utc_now(),
      user_agent: parse_user_agent(Plug.Conn.get_req_header(conn, "user-agent"))
    }
  end

  @doc """
  Converts an IP tuple like {127, 0, 0, 1} to a string "127.0.0.1".
  Returns nil if the input is nil.
  If input is already a string, returns it as-is.
  """
  def parse_ip(nil), do: nil
  def parse_ip(ip) when is_binary(ip), do: ip

  def parse_ip(ip_tuple) when is_tuple(ip_tuple) do
    ip_tuple
    |> Tuple.to_list()
    |> Enum.join(".")
  end

  @doc """
  Extracts a user agent string from request headers.
  Handles various input formats (list, single value, nil).
  """
  def parse_user_agent(nil), do: nil
  def parse_user_agent([]), do: nil
  def parse_user_agent([value | _]), do: value
  def parse_user_agent(value) when is_binary(value), do: value
end
