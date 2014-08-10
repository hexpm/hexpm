defmodule HexWeb.TarTest do
  use HexWebTest.Case

  @versions [2, 3]

  Enum.each(@versions, fn version ->
    test "retrieve metadata (VERSION #{version})" do
      meta  = %{"app" => "ecto", "version" => "1.2.3"}
      files = [{"README", "pls read me"}]
      tar   = create_tar(unquote(version), meta, files)
      assert {:ok, ^meta, _checksum} = HexWeb.Tar.metadata(tar)
    end
  end)
end
