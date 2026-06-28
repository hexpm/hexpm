defmodule Hexpm.Geo.LocalTest do
  use ExUnit.Case, async: false

  alias Hexpm.Geo.Local

  setup do
    prev = Application.get_env(:hexpm, :geo_local_lookups)
    on_exit(fn -> restore(prev) end)
    :ok
  end

  defp restore(nil), do: Application.delete_env(:hexpm, :geo_local_lookups)
  defp restore(value), do: Application.put_env(:hexpm, :geo_local_lookups, value)

  test "returns nil when no lookup map is configured" do
    Application.delete_env(:hexpm, :geo_local_lookups)
    assert Local.lookup_country("1.2.3.4") == nil
  end

  test "returns nil for an IP not present in the configured map" do
    Application.put_env(:hexpm, :geo_local_lookups, %{
      "1.2.3.4" => %{iso_code: "US", name: "United States"}
    })

    assert Local.lookup_country("9.9.9.9") == nil
  end

  test "returns the configured country for a matching IP" do
    Application.put_env(:hexpm, :geo_local_lookups, %{
      "1.2.3.4" => %{iso_code: "DE", name: "Germany"}
    })

    assert Local.lookup_country("1.2.3.4") == %{iso_code: "DE", name: "Germany"}
  end
end
