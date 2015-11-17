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
    version0 = %Version{major: 0, minor: 0, patch: 1, pre: ["dev", 0, 1]}
    version1 = %Version{major: 0, minor: 0, patch: 2, pre: []}
    version2 = %Version{major: 0, minor: 2, patch: 99, pre: []}
    version3 = %Version{major: 2, minor: 0, patch: 2, pre: []}

    assert Util.mix_snippet_version(version0) == "~> 0.0.1-dev.0.1"
    assert Util.mix_snippet_version(version1) == "~> 0.0.2"
    assert Util.mix_snippet_version(version2) == "~> 0.2.99"
    assert Util.mix_snippet_version(version3) == "~> 2.0"
  end

  test "rebar config snippet" do
    version0 = %Version{major: 0, minor: 0, patch: 1, pre: ["dev", 0, 1]}
    version1 = %Version{major: 0, minor: 0, patch: 2, pre: []}
    version2 = %Version{major: 0, minor: 2, patch: 99, pre: []}
    version3 = %Version{major: 2, minor: 0, patch: 2, pre: []}

    assert Util.rebar_snippet_version(version0) == "0.0.1-dev.0.1"
    assert Util.rebar_snippet_version(version1) == "0.0.2"
    assert Util.rebar_snippet_version(version2) == "0.2.99"
    assert Util.rebar_snippet_version(version3) == "2.0.2"
  end
end
