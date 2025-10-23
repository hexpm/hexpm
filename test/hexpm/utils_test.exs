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

  describe "safe_int/1" do
    test "handles various input types" do
      assert Utils.safe_int("707") == 707
      assert Utils.safe_int("abc") == nil
      assert Utils.safe_int(nil) == nil
      assert Utils.safe_int(%{"page" => "707"}) == nil
      assert Utils.safe_int(707) == nil
    end
  end

  describe "safe_date/1" do
    test "handles various input types" do
      assert Utils.safe_date("2024-01-15") == ~D[2024-01-15]
      assert Utils.safe_date("invalid") == nil
      assert Utils.safe_date(nil) == nil
      assert Utils.safe_date(%{"date" => "2024-01-15"}) == nil
    end
  end

  describe "safe_to_atom/2" do
    test "handles various input types" do
      assert Utils.safe_to_atom("foo", ~w(foo bar)) == :foo
      assert Utils.safe_to_atom("baz", ~w(foo bar)) == nil
      assert Utils.safe_to_atom(%{"key" => "foo"}, ~w(foo bar)) == nil
    end
  end
end
