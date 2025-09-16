defmodule HexpmWeb.DeviceViewTest do
  use HexpmWeb.ConnCase, async: true

  alias HexpmWeb.DeviceView

  describe "format_user_code/1" do
    test "formats 8-character code with hyphen" do
      assert DeviceView.format_user_code("ABCD1234") == "ABCD-1234"
    end

    test "handles nil and empty string" do
      assert DeviceView.format_user_code(nil) == ""
      assert DeviceView.format_user_code("") == ""
    end

    test "returns code unchanged if not 8 characters" do
      assert DeviceView.format_user_code("ABC") == "ABC"
      assert DeviceView.format_user_code("ABCD12345") == "ABCD12345"
    end
  end

  describe "normalize_user_code/1" do
    test "removes hyphens and converts to uppercase" do
      assert DeviceView.normalize_user_code("abcd-1234") == "ABCD1234"
      assert DeviceView.normalize_user_code("ABCD-1234") == "ABCD1234"
    end

    test "handles input without hyphens" do
      assert DeviceView.normalize_user_code("abcd1234") == "ABCD1234"
      assert DeviceView.normalize_user_code("ABCD1234") == "ABCD1234"
    end

    test "handles nil and empty string" do
      assert DeviceView.normalize_user_code(nil) == ""
      assert DeviceView.normalize_user_code("") == ""
    end

    test "removes multiple hyphens" do
      assert DeviceView.normalize_user_code("ab-cd-12-34") == "ABCD1234"
    end
  end
end