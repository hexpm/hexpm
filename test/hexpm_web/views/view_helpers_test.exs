defmodule HexpmWeb.ViewHelpersTest do
  use ExUnit.Case, async: true
  import HexpmWeb.ViewHelpers

  describe "safe_url/1" do
    test "allows http URLs" do
      assert safe_url("http://example.com") == "http://example.com"
    end

    test "allows https URLs" do
      assert safe_url("https://example.com/path?q=1") == "https://example.com/path?q=1"
    end

    test "allows mailto URLs" do
      assert safe_url("mailto:user@example.com") == "mailto:user@example.com"
    end

    test "blocks javascript protocol" do
      assert safe_url("javascript:alert(1)") == "#"
    end

    test "blocks data protocol" do
      assert safe_url("data:text/html,<h1>xss</h1>") == "#"
    end

    test "blocks bare strings without scheme" do
      assert safe_url("example.com") == "#"
    end

    test "handles nil" do
      assert safe_url(nil) == "#"
    end
  end

  describe "main_repository?/1" do
    test "returns true for repository_id 1" do
      assert main_repository?(%{repository_id: 1}) == true
    end

    test "returns false for other repository ids" do
      assert main_repository?(%{repository_id: 2}) == false
      assert main_repository?(%{repository_id: 99}) == false
    end

    test "returns false for missing repository_id" do
      assert main_repository?(%{}) == false
      assert main_repository?(nil) == false
    end
  end

  describe "human_number_space" do
    test "without compaction" do
      assert human_number_space(0) == "0"
      assert human_number_space(10_000) == "10 000"
      assert human_number_space("10000") == "10 000"
    end

    test "with compaction" do
      assert human_number_space(0, 3) == "0"
      assert human_number_space(100, 3) == "100"
      assert human_number_space(1234, 3) == "1.2K"
      assert human_number_space(1234, 4) == "1 234"
      assert human_number_space(10_000, 3) == "10K"
      assert human_number_space(10_124, 5) == "10 124"

      assert human_number_space(100_000, 5) == "100K"
      assert human_number_space(100_124, 5) == "100.1K"
      assert human_number_space(100_124, 6) == "100 124"

      assert human_number_space(1_000_000, 5) == "1M"
      assert human_number_space(11_956_003, 5) == "11.96M"
      assert human_number_space(11_956_003, 8) == "11 956 003"

      assert human_number_space(191_956_003, 6) == "191.96M"
      assert human_number_space(191_956_003, 5) == "192M"

      assert human_number_space(800_000_000_000, 5) == "800B"
      assert human_number_space(800_191_956_003, 5) == "800.2B"
      assert human_number_space(800_191_956_003, 50) == "800 191 956 003"
    end
  end
end
