defmodule HexpmWeb.Components.FilterCheatsheetTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest
  import HexpmWeb.Components.FilterCheatsheet

  test "lists every filter operator with an example" do
    html = render_component(&cheatsheet/1, %{id: "sheet"})

    for op <- ~w(name: description: depends: build_tool: updated_after: extra:) do
      assert html =~ op, "missing #{op}"
    end

    assert html =~ "mix"
    assert html =~ "phoenix"
  end
end
