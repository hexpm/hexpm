defmodule HexWeb.UtilTest do
  use HexWebTest.Case
  alias HexWeb.Util

  test "safe search" do
    string = "& *  WSDL  SOAP   "
    assert Util.safe_search(string) == "WSDL  SOAP"

    input = "WSDL/SOAP*()"
    assert Util.safe_search(input) == "WSDL SOAP"
  end

  test "mix config snippet" do
    alpha_version   = %Version{major: 0, minor: 0, patch: 2}
    beta_version    = %Version{major: 0, minor: 2, patch: 99}
    stable_version  = %Version{major: 2, minor: 0, patch: 2}

    assert Util.mix_snippet_version(alpha_version)  == "~> 0.0.2"
    assert Util.mix_snippet_version(beta_version)   == "~> 0.2.99"
    assert Util.mix_snippet_version(stable_version) == "~> 2.0"
  end

  test "rebar config snippet" do
    alpha_version   = %Version{major: 0, minor: 0, patch: 2}
    beta_version    = %Version{major: 0, minor: 2, patch: 99}
    stable_version  = %Version{major: 2, minor: 0, patch: 2}

    assert Util.rebar_snippet_version(alpha_version)  == "0.0.2"
    assert Util.rebar_snippet_version(beta_version)   == "0.2.99"
    assert Util.rebar_snippet_version(stable_version) == "2.0.2"
  end
end
