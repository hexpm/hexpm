defmodule Hexpm.UtilsTest do
  use ExUnit.Case, async: true

  alias Hexpm.Utils

  describe "datetime_to_rfc2822" do
    test "formats sample timestamps correctly" do
      assert Utils.datetime_to_rfc2822(~U[2002-09-07 09:42:31Z]) ==
               "Sat, 07 Sep 2002 09:42:31 GMT"

      assert Utils.datetime_to_rfc2822(~U[2020-02-23 19:47:26Z]) ==
               "Sun, 23 Feb 2020 19:47:26 GMT"
    end
  end
end
