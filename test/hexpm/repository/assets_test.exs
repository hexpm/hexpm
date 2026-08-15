defmodule Hexpm.Repository.AssetsTest do
  use ExUnit.Case, async: true

  alias Hexpm.Repository.Assets

  test "file_checksum/1 calculates the SHA-256 checksum without loading the file at once" do
    path = Hexpm.TmpDir.tmp_file("asset-checksum")
    contents = :binary.copy("checksum contents", 10_000)
    File.write!(path, contents)

    assert Assets.file_checksum(path) == :crypto.hash(:sha256, contents)
  end
end
