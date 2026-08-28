defmodule HexpmWeb.Docs.FilesTest do
  use ExUnit.Case, async: true

  alias HexpmWeb.Docs.Files

  test "kinds/0 returns the seven kinds in canonical order" do
    assert Files.kinds() ==
             [:readme, :changelog, :license, :security, :support, :acknowledgments, :threat_model]
  end

  test "label/1" do
    assert Files.label(:readme) == "Readme"
    assert Files.label(:threat_model) == "Threat Model"
    assert Files.label(:acknowledgments) == "Acknowledgments"
  end

  test "parse_segment/1" do
    assert Files.parse_segment("changelog") == :changelog
    assert Files.parse_segment("threat_model") == :threat_model
    assert Files.parse_segment("bogus") == nil
    assert Files.parse_segment("threat-model") == nil
  end

  describe "resolve/2" do
    test "finds exact conventional names" do
      assert Files.resolve(:changelog, ["CHANGELOG.md", "mix.exs"]) == "CHANGELOG.md"
      assert Files.resolve(:license, ["LICENSE"]) == "LICENSE"
      assert Files.resolve(:security, ["SECURITY.md"]) == "SECURITY.md"
    end

    test "is case-insensitive on the basename" do
      assert Files.resolve(:changelog, ["Changelog.md"]) == "Changelog.md"
      assert Files.resolve(:changelog, ["changelog.md"]) == "changelog.md"
      assert Files.resolve(:changelog, ["ChangeLog"]) == "ChangeLog"
    end

    test "prefers .md, then .markdown, then bare, then .txt" do
      files = ["CHANGELOG.txt", "CHANGELOG", "CHANGELOG.markdown", "CHANGELOG.md"]
      assert Files.resolve(:changelog, files) == "CHANGELOG.md"

      assert Files.resolve(:changelog, ["CHANGELOG.txt", "CHANGELOG", "CHANGELOG.markdown"]) ==
               "CHANGELOG.markdown"

      assert Files.resolve(:changelog, ["CHANGELOG.txt", "CHANGELOG"]) == "CHANGELOG"
      assert Files.resolve(:changelog, ["CHANGELOG.txt"]) == "CHANGELOG.txt"
    end

    test "breaks ties within an extension lexicographically" do
      assert Files.resolve(:changelog, ["Changelog.md", "CHANGELOG.md"]) == "CHANGELOG.md"
    end

    test "only matches the tarball root" do
      assert Files.resolve(:changelog, ["docs/CHANGELOG.md", "lib/foo.ex"]) == nil
    end

    test "does not match unrelated extensions or prefixed names" do
      assert Files.resolve(:license, ["LICENSE.rapidxml"]) == nil
      assert Files.resolve(:readme, ["README.ja.md"]) == nil
    end

    test "acknowledgments matches both spellings" do
      assert Files.resolve(:acknowledgments, ["ACKNOWLEDGMENTS.md"]) == "ACKNOWLEDGMENTS.md"
      assert Files.resolve(:acknowledgments, ["ACKNOWLEDGEMENTS.md"]) == "ACKNOWLEDGEMENTS.md"
    end

    test "threat_model matches separator variants" do
      assert Files.resolve(:threat_model, ["THREAT_MODEL.md"]) == "THREAT_MODEL.md"
      assert Files.resolve(:threat_model, ["THREATMODEL.md"]) == "THREATMODEL.md"
      assert Files.resolve(:threat_model, ["THREAT-MODEL.md"]) == "THREAT-MODEL.md"
      assert Files.resolve(:threat_model, ["threat-model"]) == "threat-model"
    end

    test "readme resolution matches conventional names" do
      assert Files.resolve(:readme, ["README.md", "LICENSE"]) == "README.md"
      assert Files.resolve(:readme, ["readme.markdown"]) == "readme.markdown"
      # bare now beats .txt (intentional change from the old README list)
      assert Files.resolve(:readme, ["README.txt", "README"]) == "README"
    end
  end

  test "available_kinds/1 returns kinds in canonical order" do
    files = ["LICENSE", "README.md", "CHANGELOG.md", "mix.exs", "lib/a.ex"]
    assert Files.available_kinds(files) == [:readme, :changelog, :license]
    assert Files.available_kinds(["mix.exs"]) == []
  end
end
