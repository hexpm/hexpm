defmodule HexpmWeb.Components.FileSelectorTest do
  use ExUnit.Case, async: true

  alias HexpmWeb.Components.FileSelector

  test "filter ranks matches and caps results" do
    files = for index <- 1..150, do: "lib/file_#{index}.ex"

    assert length(FileSelector.filter(files, "")) == 100

    assert ["lib/file_149.ex"] = FileSelector.filter(files, "149")
  end

  test "filter_by preserves distinct entries with the same displayed path" do
    files = [%{id: 1, path: "?.ex"}, %{id: 2, path: "?.ex"}]

    assert FileSelector.filter_by(files, & &1.path, "?") == files
  end
end
