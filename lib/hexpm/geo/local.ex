defmodule Hexpm.Geo.Local do
  @moduledoc """
  Geo implementation used in dev and test.

  Looks up IPs in a static map configured under `:hexpm, :geo_local_lookups`,
  defaulting to `%{}` (which makes the module behave as a no-op). Useful for
  exercising the audit-log location UI locally without a real `.mmdb`, and for
  injecting specific results in tests.

      # config/dev.exs
      config :hexpm,
        geo_local_lookups: %{
          "127.0.0.1" => %{iso_code: "US", name: "United States"},
          "::1" => %{iso_code: "US", name: "United States"}
        }

      # in a test
      Application.put_env(:hexpm, :geo_local_lookups, %{
        "1.2.3.4" => %{iso_code: "DE", name: "Germany"}
      })

  IPs not present in the map resolve to `nil`.
  """
  @behaviour Hexpm.Geo

  @impl Hexpm.Geo
  def lookup_country(ip) when is_binary(ip) do
    :hexpm
    |> Application.get_env(:geo_local_lookups, %{})
    |> Map.get(ip)
  end
end
