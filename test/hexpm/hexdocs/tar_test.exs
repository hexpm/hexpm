defmodule Hexpm.Hexdocs.TarTest do
  use Hexpm.DataCase, async: true

  alias Hexpm.Hexdocs.Tar

  test "unpacks docs archives" do
    path = Hexpm.TmpDir.tmp_file("docs-tarball")
    File.write!(path, create_docs_tar([{"index.html", "contents"}, {"assets/app.js", "js"}]))

    assert {dir, files} = Tar.unpack_to_dir!({:file, path})
    assert Enum.sort(files) == ["assets/app.js", "index.html"]
    assert File.read!(Path.join(dir, "index.html")) == "contents"
  end

  test "raises a contextual error for invalid archives" do
    path = Hexpm.TmpDir.tmp_file("docs-tarball")
    File.write!(path, "invalid")

    assert_raise Tar.UnpackError, ~r/Failed to unpack hexpm\/package 1\.0\.0:/, fn ->
      Tar.unpack_to_dir!({:file, path},
        repository: "hexpm",
        package: "package",
        version: "1.0.0"
      )
    end
  end

  test "rejects semver-named root paths" do
    path = Hexpm.TmpDir.tmp_file("docs-tarball")
    File.write!(path, create_docs_tar([{"1.0.0/index.html", "contents"}]))

    assert_raise Tar.UnpackError, ~r/root file or directory name not allowed/, fn ->
      Tar.unpack_to_dir!({:file, path},
        repository: "hexpm",
        package: "package",
        version: "1.0.0"
      )
    end
  end
end
