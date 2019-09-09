defmodule HexpmWeb.ViewHelpersTest do
  use ExUnit.Case, async: true
  import HexpmWeb.ViewHelpers

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
