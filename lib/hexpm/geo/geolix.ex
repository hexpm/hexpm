defmodule Hexpm.Geo.Geolix do
  @moduledoc """
  Resolves IPs to a country using an MMDB-format IP-to-country database via
  the `:geolix` library. The default deployment uses the free
  [DB-IP IP-to-Country Lite](https://db-ip.com/db/download/ip-to-country-lite)
  database (CC-BY-4.0); any other MaxMind-compatible MMDB country database
  works equivalently. The database is configured under `config :geolix` with
  the id `:country` (see `config/runtime.exs`).
  """
  @behaviour Hexpm.Geo

  @impl Hexpm.Geo
  def lookup_country(ip) when is_binary(ip) do
    ip
    |> Geolix.lookup(where: :country)
    |> parse_result()
  end

  @doc """
  Parses the raw return value of `Geolix.lookup/2` into a `%{iso_code, name}`
  map, or `nil` if no country could be resolved.

  `Geolix.lookup/2` returns one of two shapes depending on whether geolix's
  MMDB2 adapter recognizes the file's `database_type` metadata string:

    * Recognized (e.g. MaxMind "GeoLite2-Country") — a `Result.Country`
      struct whose inner country record has `:name` pre-populated from
      `names[locale]`.
    * Unrecognized (e.g. DB-IP, whose `database_type` is not in geolix's
      mapping) — the raw decoded map, where `:name` is NEVER set and only
      `:names` is present.

  The DB-IP path is therefore always the raw-map path, so the `names` →
  English fallback in `country_name/2` is REQUIRED, not dead code: it is the
  only source of a human name there. `fetch/2` additionally accepts atom OR
  string keys, so the parser stays correct regardless of the decoder's
  `map_keys` option.
  """
  def parse_result(result) when is_map(result) do
    with country when is_map(country) <- fetch(result, :country),
         iso when is_binary(iso) and iso != "ZZ" <- fetch(country, :iso_code) do
      %{iso_code: iso, name: country_name(country, iso)}
    else
      _ -> nil
    end
  end

  def parse_result(_), do: nil

  defp country_name(country, iso) do
    fetch(country, :name) || english_name(fetch(country, :names)) || iso
  end

  defp english_name(names) when is_map(names), do: fetch(names, :en)
  defp english_name(_), do: nil

  # MMDB results use atom keys by default, but may use string keys under a
  # `result_as: :raw` lookup with custom decoder options. Accept either.
  defp fetch(map, key) when is_map(map),
    do: Map.get(map, key) || Map.get(map, Atom.to_string(key))

  defp fetch(_, _), do: nil
end
