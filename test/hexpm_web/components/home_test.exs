defmodule HexpmWeb.Components.HomeTest do
  use ExUnit.Case, async: true
  use Phoenix.Component

  import HexpmWeb.Components.Home
  import Phoenix.LiveViewTest

  test "inline code has no surrounding whitespace" do
    html = render_component(&inline_code/1, %{})

    assert [{"span", _attributes, ["{deps, [hackney]}"]}] =
             LazyHTML.from_fragment(html) |> LazyHTML.to_tree()
  end

  defp inline_code(assigns) do
    ~H"""
    <.code_inline>{"{deps, [hackney]}"}</.code_inline>
    """
  end
end
