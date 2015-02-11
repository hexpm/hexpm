defmodule HexWeb.TarTest do
  use HexWebTest.Case

  test "retrieve metadata" do
    meta  = %{"app" => "ecto", "version" => "1.2.3"}
    files = [{"README", "pls read me"}]
    tar   = create_tar(meta, files)
    assert {:ok, ^meta, _checksum} = HexWeb.Tar.metadata(tar)
  end
end
