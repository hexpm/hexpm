defmodule Hexpm.Geo.GeolixTest do
  use ExUnit.Case, async: true

  alias Hexpm.Geo.Geolix
  # Aliased explicitly because `alias Hexpm.Geo.Geolix` above shadows the
  # top-level `Geolix` namespace from the geolix library.
  alias Elixir.Geolix.Adapter.MMDB2.Record.Country, as: GeolixCountryRecord
  alias Elixir.Geolix.Adapter.MMDB2.Result.Country, as: GeolixCountryResult

  describe "parse_result/1 with real geolix output shapes" do
    test "handles a Result.Country struct (recognized database_type, e.g. GeoLite2)" do
      # When geolix recognizes the database_type it returns a struct whose
      # inner country record has :name pre-populated from names[locale].
      country =
        GeolixCountryRecord.from(
          %{iso_code: "US", names: %{en: "United States", de: "Vereinigte Staaten"}},
          :en
        )

      result = %GeolixCountryResult{country: country}

      assert Geolix.parse_result(result) == %{iso_code: "US", name: "United States"}
    end

    test "handles a raw atom-keyed map (unrecognized database_type, e.g. DB-IP)" do
      # When geolix does NOT recognize the database_type it returns the raw
      # decoded map: atom keys, sibling records, and NO :name on the country —
      # only :names. This is the DB-IP path; the name must come from names[:en].
      result = %{
        continent: %{geoname_id: 6_255_149, code: "NA", names: %{en: "North America"}},
        country: %{
          geoname_id: 6_252_001,
          is_in_european_union: false,
          iso_code: "US",
          names: %{en: "United States", fr: "États-Unis"}
        },
        registered_country: %{iso_code: "US", names: %{en: "United States"}},
        ip_address: {1, 2, 3, 4}
      }

      assert Geolix.parse_result(result) == %{iso_code: "US", name: "United States"}
    end

    test "handles a string-keyed raw map (result_as: :raw with string decoder keys)" do
      # If the decoder is ever configured with string keys, the raw map uses
      # string keys throughout; the parser must still resolve it.
      result = %{"country" => %{"iso_code" => "FR", "names" => %{"en" => "France"}}}

      assert Geolix.parse_result(result) == %{iso_code: "FR", name: "France"}
    end
  end

  describe "parse_result/1" do
    test "extracts iso_code and resolved name" do
      result = %{country: %{iso_code: "US", name: "United States"}}
      assert Geolix.parse_result(result) == %{iso_code: "US", name: "United States"}
    end

    test "falls back to the english name when :name is absent" do
      result = %{country: %{iso_code: "US", names: %{en: "United States"}}}
      assert Geolix.parse_result(result) == %{iso_code: "US", name: "United States"}
    end

    test "falls back to the iso code when no name is available" do
      result = %{country: %{iso_code: "DE"}}
      assert Geolix.parse_result(result) == %{iso_code: "DE", name: "DE"}
    end

    test "returns nil when the country has no iso_code" do
      assert Geolix.parse_result(%{country: %{}}) == nil
    end

    test "returns nil for a missing/empty/nil lookup result" do
      assert Geolix.parse_result(%{}) == nil
      assert Geolix.parse_result(nil) == nil
      assert Geolix.parse_result({:error, :not_found}) == nil
    end

    test "returns nil for ZZ (DB-IP unknown/unresolvable IP pseudo-code)" do
      assert Geolix.parse_result(%{country: %{iso_code: "ZZ", names: %{en: "Unknown"}}}) == nil
    end
  end
end
