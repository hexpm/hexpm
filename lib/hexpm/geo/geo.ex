defmodule Hexpm.Geo do
  @moduledoc """
  Resolves IP address strings to a country, for display in audit logs.

  The active implementation is selected via the `:geo_impl` application
  environment. See `Hexpm.Geo.Local` (dev/test) and `Hexpm.Geo.Geolix` (prod).
  """

  @typedoc "A resolved country, or nil when the IP could not be located."
  @type country :: %{iso_code: String.t(), name: String.t()} | nil

  @callback lookup_country(ip :: String.t()) :: country()

  defp impl(), do: Application.get_env(:hexpm, :geo_impl)

  @doc """
  Resolves an IP string to a `%{iso_code, name}` map, or nil when it cannot be
  located (including unresolvable/private IPs and a nil input).
  """
  @spec lookup_country(String.t() | nil) :: country()
  def lookup_country(nil), do: nil
  def lookup_country(ip) when is_binary(ip), do: impl().lookup_country(ip)

  @doc """
  Converts a two-letter ISO 3166-1 alpha-2 country code into its flag emoji
  using Unicode regional indicator symbols. Returns "" for any other input.
  """
  @spec flag_emoji(String.t()) :: String.t()
  def flag_emoji(<<a, b>>) when a in ?A..?Z and b in ?A..?Z do
    <<127_397 + a::utf8, 127_397 + b::utf8>>
  end

  def flag_emoji(_), do: ""
end
