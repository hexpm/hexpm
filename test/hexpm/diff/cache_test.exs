defmodule Hexpm.Diff.CacheTest do
  use Hexpm.DataCase, async: true

  alias Hexpm.Diff.Cache

  defp put(key), do: Hexpm.Store.put(:diff_bucket, key, "{}", [])
  defp keys(), do: :diff_bucket |> Hexpm.Store.list("") |> Enum.sort()

  describe "delete_package/2" do
    test "deletes the package's metadata and diff objects" do
      put("metadata/foo-1.0.0-2.0.0-123.json")
      put("diffs/foo-1.0.0-2.0.0-123-diff-0.json")
      put("diffs/foo-1.0.0-2.0.0-123-diff-1.json")

      assert :ok = Cache.delete_package("hexpm", "foo")

      assert keys() == []
    end

    test "leaves a package whose name starts with the same characters" do
      put("metadata/foo-1.0.0-2.0.0-123.json")
      put("metadata/foobar-1.0.0-2.0.0-456.json")
      put("diffs/foo_bar-1.0.0-2.0.0-789-diff-0.json")

      assert :ok = Cache.delete_package("hexpm", "foo")

      assert keys() == [
               "diffs/foo_bar-1.0.0-2.0.0-789-diff-0.json",
               "metadata/foobar-1.0.0-2.0.0-456.json"
             ]
    end

    test "deletes only the given repository's objects" do
      put("metadata/foo-1.0.0-2.0.0-123.json")
      put("repos/acme/metadata/foo-1.0.0-2.0.0-123.json")
      put("repos/other/diffs/foo-1.0.0-2.0.0-123-diff-0.json")

      assert :ok = Cache.delete_package("acme", "foo")

      assert keys() == [
               "metadata/foo-1.0.0-2.0.0-123.json",
               "repos/other/diffs/foo-1.0.0-2.0.0-123-diff-0.json"
             ]
    end

    test "does nothing when the package has no cached diffs" do
      put("metadata/other-1.0.0-2.0.0-123.json")

      assert :ok = Cache.delete_package("hexpm", "foo")

      assert keys() == ["metadata/other-1.0.0-2.0.0-123.json"]
    end
  end
end
