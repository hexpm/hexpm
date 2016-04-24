defmodule HexWeb.TarTest do
  use ExUnit.Case, async: true
  import HexWeb.TestHelpers

  test "retrieve metadata" do
    meta  = %{"app" => "ecto", "version" => "1.2.3"}
    files = [{"README", "pls read me"}]
    tar   = create_tar(meta, files)
    assert {:ok, %{"app" => "ecto", "version" => "1.2.3"}, _checksum} = HexWeb.Tar.metadata(tar)
  end
end
