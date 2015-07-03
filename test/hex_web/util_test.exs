defmodule HexWeb.UtilTest do
  use HexWebTest.Case
  alias HexWeb.Util

  test "safe search" do
    string = "& *  WSDL  SOAP   "
    assert Util.safe_search(string) == "WSDL  SOAP"

    input = "WSDL/SOAP*()"
    assert Util.safe_search(input) == "WSDL SOAP"
  end
end
