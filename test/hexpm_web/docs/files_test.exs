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

    test "prefers .md, then .markdown, then .txt, then bare" do
      files = ["CHANGELOG.txt", "CHANGELOG", "CHANGELOG.markdown", "CHANGELOG.md"]
      assert Files.resolve(:changelog, files) == "CHANGELOG.md"

      assert Files.resolve(:changelog, ["CHANGELOG.txt", "CHANGELOG", "CHANGELOG.markdown"]) ==
               "CHANGELOG.markdown"

      assert Files.resolve(:changelog, ["CHANGELOG.txt", "CHANGELOG"]) == "CHANGELOG.txt"
      assert Files.resolve(:changelog, ["CHANGELOG"]) == "CHANGELOG"
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
      assert Files.resolve(:readme, ["README.txt", "README"]) == "README.txt"
    end

    test "does not match a filename ending in a bare trailing dot" do
      assert Files.resolve(:readme, ["README."]) == nil
      assert Files.resolve(:readme, ["README"]) == "README"
      assert Files.resolve(:readme, ["README.md"]) == "README.md"
    end

    test "tolerates malformed file lists instead of raising" do
      assert Files.resolve(:readme, ["README.md", nil]) == "README.md"
      assert Files.resolve(:readme, [1, "README.md"]) == "README.md"
      assert Files.resolve(:readme, [["nested"], "README.md"]) == "README.md"
      assert Files.resolve(:readme, [%{}]) == nil
      assert Files.resolve(:readme, %{"files" => []}) == nil
      assert Files.resolve(:readme, nil) == nil
    end
  end

  test "available_kinds/1 returns kinds in canonical order" do
    files = ["LICENSE", "README.md", "CHANGELOG.md", "mix.exs", "lib/a.ex"]
    assert Files.available_kinds(files) == [:readme, :changelog, :license]
    assert Files.available_kinds(["mix.exs"]) == []
  end

  test "available_kinds/1 tolerates malformed file lists instead of raising" do
    assert Files.available_kinds(["README.md", nil, 1, ["x"], %{}]) == [:readme]
    assert Files.available_kinds(%{"files" => []}) == []
    assert Files.available_kinds(nil) == []
  end

  describe "resolve_all/1" do
    test "matches resolve/2 for every kind on a mixed file list" do
      files = [
        "README.md",
        "CHANGELOG.txt",
        "LICENSE",
        "docs/SECURITY.md",
        "support.MD",
        "ACKNOWLEDGEMENTS.markdown",
        "THREAT-MODEL.md",
        nil,
        1,
        ["nested"],
        %{}
      ]

      resolved = Files.resolve_all(files)

      for kind <- Files.kinds() do
        assert Map.get(resolved, kind) == Files.resolve(kind, files)
      end
    end

    test "returns an empty map for a malformed file list" do
      assert Files.resolve_all(%{"files" => []}) == %{}
      assert Files.resolve_all(nil) == %{}
    end
  end

  describe "present_kinds/1" do
    test "returns kinds in canonical order regardless of map insertion order" do
      resolved = %{
        threat_model: "THREAT_MODEL.md",
        readme: "README.md",
        license: "LICENSE"
      }

      assert Files.present_kinds(resolved) == [:readme, :license, :threat_model]
    end

    test "returns an empty list for an empty map" do
      assert Files.present_kinds(%{}) == []
    end
  end
end
