defmodule Hexpm.GeoTest do
  use ExUnit.Case, async: true

  import Mox

  setup :verify_on_exit!

  # All ISO 3166-1 alpha-2 codes per https://www.iban.com/country-codes.
  # Used to verify flag_emoji/1 produces a non-empty result for every valid code
  # and to confirm that pseudo-codes we suppress (ZZ, XK) are not in the list.
  @iso_3166_1_alpha2 ~w(
    AF AX AL DZ AS AD AO AI AQ AG AR AM AW AU AT AZ BS BH BD BB BY BE BZ BJ BM
    BT BO BQ BA BW BV BR IO BN BG BF BI CV KH CM CA KY CF TD CL CN CX CC CO KM
    CD CG CK CR CI HR CU CW CY CZ DK DJ DM DO EC EG SV GQ ER EE SZ ET FK FO FJ
    FI FR GF PF TF GA GM GE DE GH GI GR GL GD GP GU GT GG GN GW GY HT HM VA HN
    HK HU IS IN ID IR IQ IE IM IL IT JM JP JE JO KZ KE KI KP KR KW KG LA LV LB
    LS LR LY LI LT LU MO MK MG MW MY MV ML MT MH MQ MR MU YT MX FM MD MC MN ME
    MS MA MZ MM NA NR NP NL NC NZ NI NE NG NU NF MP NO OM PK PW PS PA PG PY PE
    PH PN PL PT PR QA RE RO RU RW BL SH KN LC MF PM VC WS SM ST SA SN RS SC SL
    SG SX SK SI SB SO ZA GS SS ES LK SD SR SJ SE CH SY TW TJ TZ TH TL TG TK TO
    TT TN TR TM TC TV UG UA AE GB UM US UY UZ VU VE VN VG VI WF EH YE ZM ZW
  )

  describe "flag_emoji/1" do
    test "converts a two-letter ISO code to a flag emoji" do
      assert Hexpm.Geo.flag_emoji("US") == <<0x1F1FA::utf8, 0x1F1F8::utf8>>
      assert Hexpm.Geo.flag_emoji("DE") == <<0x1F1E9::utf8, 0x1F1EA::utf8>>
    end

    test "produces a non-empty result for every ISO 3166-1 alpha-2 code" do
      for code <- @iso_3166_1_alpha2 do
        assert Hexpm.Geo.flag_emoji(code) != "",
               "expected non-empty emoji for #{code}"
      end
    end

    test "ZZ (DB-IP unknown pseudo-code) is not in the ISO standard" do
      refute "ZZ" in @iso_3166_1_alpha2
    end

    test "XK (Kosovo, DB-IP unofficial code) is not in the ISO standard" do
      refute "XK" in @iso_3166_1_alpha2
    end

    test "returns empty string for anything that is not a 2-letter A-Z code" do
      assert Hexpm.Geo.flag_emoji("USA") == ""
      assert Hexpm.Geo.flag_emoji("u") == ""
      assert Hexpm.Geo.flag_emoji("us") == ""
      assert Hexpm.Geo.flag_emoji("") == ""
    end
  end

  describe "lookup_country/1" do
    test "returns nil for a nil IP without calling the implementation" do
      assert Hexpm.Geo.lookup_country(nil) == nil
    end

    test "delegates a binary IP to the configured implementation" do
      # config/test.exs sets geo_impl: Hexpm.Geo.Mock
      expect(Hexpm.Geo.Mock, :lookup_country, fn "8.8.8.8" ->
        %{iso_code: "US", name: "United States"}
      end)

      assert Hexpm.Geo.lookup_country("8.8.8.8") == %{iso_code: "US", name: "United States"}
    end
  end
end
