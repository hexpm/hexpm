defmodule Hexpm.Docs.FilesTest do
  use ExUnit.Case, async: true

  alias Hexpm.Docs.Files

  test "kinds/0 returns the seven kinds in canonical order" do
    assert Files.kinds() ==
             [:readme, :changelog, :license, :security, :support, :acknowledgments, :threat_model]
  end

  test "label/1" do
    assert Files.label(:readme) == "Readme"
    assert Files.label(:threat_model) == "Threat Model"
    assert Files.label(:acknowledgments) == "Acknowledgments"
  end

  test "label/1 degrades to the atom's string form for an unrecognized kind instead of raising" do
    assert Files.label(:bogus) == "bogus"
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

    test "is case-insensitive on the basename and extension" do
      assert Files.resolve(:changelog, ["Changelog.md"]) == "Changelog.md"
      assert Files.resolve(:changelog, ["changelog.md"]) == "changelog.md"
      assert Files.resolve(:changelog, ["ChangeLog"]) == "ChangeLog"
      assert Files.resolve(:readme, ["readme.MD"]) == "readme.MD"
    end

    test "prefers .md, then .markdown, then .txt, then bare -- matching Preview's existing order" do
      assert Files.resolve(:changelog, [
               "CHANGELOG",
               "CHANGELOG.txt",
               "CHANGELOG.markdown",
               "CHANGELOG.md"
             ]) ==
               "CHANGELOG.md"

      assert Files.resolve(:changelog, ["CHANGELOG", "CHANGELOG.txt", "CHANGELOG.markdown"]) ==
               "CHANGELOG.markdown"

      assert Files.resolve(:changelog, ["CHANGELOG", "CHANGELOG.txt"]) == "CHANGELOG.txt"
      assert Files.resolve(:changelog, ["CHANGELOG"]) == "CHANGELOG"
    end

    test "breaks ties within an extension lexicographically" do
      assert Files.resolve(:changelog, ["Changelog.md", "CHANGELOG.md"]) == "CHANGELOG.md"
    end

    test "only matches the tarball root" do
      assert Files.resolve(:changelog, ["docs/CHANGELOG.md", "lib/foo.ex"]) == nil
    end

    test "does not match unrelated extensions, prefixed names, or a dangling dot" do
      assert Files.resolve(:license, ["LICENSE.rapidxml"]) == nil
      assert Files.resolve(:readme, ["README.ja.md"]) == nil
      assert Files.resolve(:readme, ["README."]) == nil
    end

    test "acknowledgments matches both spellings" do
      assert Files.resolve(:acknowledgments, ["ACKNOWLEDGMENTS.md"]) == "ACKNOWLEDGMENTS.md"
      assert Files.resolve(:acknowledgments, ["ACKNOWLEDGEMENTS.md"]) == "ACKNOWLEDGEMENTS.md"
    end

    test "threat_model matches separator variants" do
      assert Files.resolve(:threat_model, ["THREAT_MODEL.md"]) == "THREAT_MODEL.md"
      assert Files.resolve(:threat_model, ["THREATMODEL.md"]) == "THREATMODEL.md"
      assert Files.resolve(:threat_model, ["THREAT-MODEL.md"]) == "THREAT-MODEL.md"
    end
  end

  describe "resolve_all/1 and present_kinds/1" do
    test "resolve_all returns every resolvable kind in one pass" do
      files = ["README.md", "CHANGELOG.md", "LICENSE", "mix.exs", "lib/a.ex"]

      assert Files.resolve_all(files) == %{
               readme: "README.md",
               changelog: "CHANGELOG.md",
               license: "LICENSE"
             }
    end

    test "present_kinds returns kinds in canonical order" do
      resolved = %{license: "LICENSE", readme: "README.md", changelog: "CHANGELOG.md"}
      assert Files.present_kinds(resolved) == [:readme, :changelog, :license]
    end

    test "resolve_all tolerates malformed input without raising" do
      assert Files.resolve_all(["README.md", nil, 42, ["nested"], %{}]) == %{readme: "README.md"}
      assert Files.resolve_all(%{"files" => []}) == %{}
      assert Files.resolve_all(nil) == %{}
    end

    test "present_kinds on an empty result is empty" do
      assert Files.present_kinds(%{}) == []
    end

    test "a recognized basename with an unrecognized extension is not resolved" do
      assert Files.resolve_all(["LICENSE.rapidxml"]) == %{}
      assert Files.resolve(:license, ["LICENSE.rapidxml"]) == nil
    end

    test "does not fold non-ASCII homoglyphs into ASCII basenames" do
      # U+017F LATIN SMALL LETTER LONG S
      assert Files.resolve_all(["LICENſE.md"]) == %{}
      # U+0131 LATIN SMALL LETTER DOTLESS I
      assert Files.resolve_all(["lıcense.md"]) == %{}
    end
  end

  describe "resolve/2 with an unrecognized kind" do
    test "returns nil instead of raising" do
      assert Files.resolve(:bogus, ["README.md"]) == nil
    end
  end

  describe "nav_kinds/2" do
    test "includes every present kind plus the active kind even when absent" do
      resolved = %{readme: "README.md", license: "LICENSE"}
      assert Files.nav_kinds(resolved, :changelog) == [:readme, :changelog, :license]
    end

    test "does not duplicate the active kind when it is already present" do
      resolved = %{readme: "README.md", changelog: "CHANGELOG.md"}
      assert Files.nav_kinds(resolved, :changelog) == [:readme, :changelog]
    end

    test "inserts the absent active kind in canonical position, not appended" do
      resolved = %{license: "LICENSE", threat_model: "THREAT_MODEL.md"}
      assert Files.nav_kinds(resolved, :readme) == [:readme, :license, :threat_model]
    end
  end

  describe "parse_segment/1 with non-binary input" do
    test "returns nil" do
      assert Files.parse_segment(["changelog"]) == nil
      assert Files.parse_segment(nil) == nil
      assert Files.parse_segment("") == nil
      assert Files.parse_segment(:changelog) == nil
    end
  end
end
