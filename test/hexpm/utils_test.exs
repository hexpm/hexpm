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

  test "latest_valid_release_with_docs" do
    assert Utils.latest_valid_release_with_docs([]) == nil

    assert Utils.latest_valid_release_with_docs([
             %{
               has_docs: false,
               version: %Version{major: 0, minor: 0, patch: 2, pre: ["dev", 0, 1]}
             },
             %{has_docs: false, version: %Version{major: 0, minor: 0, patch: 1}}
           ]) == nil

    assert Utils.latest_valid_release_with_docs([
             %{
               has_docs: true,
               version: %Version{major: 0, minor: 0, patch: 2, pre: ["dev", 0, 1]}
             },
             %{has_docs: true, version: %Version{major: 0, minor: 0, patch: 1}}
           ]) == %{has_docs: true, version: %Version{major: 0, minor: 0, patch: 1}}
  end
end
