defmodule Hexpm.Web.ReleaseTarTest do
  use ExUnit.Case, async: true
  import Hexpm.TestHelpers

  test "retrieve metadata" do
    meta = %{"app" => "ecto", "version" => "1.2.3"}
    files = [{"README", "pls read me"}]
    tar = create_tar(meta, files)

    assert {:ok, %{"app" => "ecto", "version" => "1.2.3"}, _checksum} =
             Hexpm.Web.ReleaseTar.metadata(tar)
  end
end
