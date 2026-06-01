defmodule HexpmWeb.Readme.RendererTest do
  use ExUnit.Case, async: true

  alias HexpmWeb.Readme.Renderer

  defp render(content) do
    Renderer.render("README.md", content, "my_package", "1.0.0")
  end

  test "author fragment links resolve to the anchored heading id" do
    content = """
    [Go to install](#installation)

    ## Installation
    """

    result = render(content)

    assert result =~ ~s[<h2 id="user-content-installation">]
    assert result =~ ~s[href="#user-content-installation"]
  end

  test "numeric footnote links resolve to their target id" do
    content = """
    Reference.[^1]

    [^1]: numeric.
    """

    result = render(content)

    assert result =~ ~s[href="#fn-1"]
    assert result =~ ~s[<li id="fn-1">]
  end

  test "named footnote links resolve to their target id" do
    content = """
    Reference.[^note]

    [^note]: named.
    """

    result = render(content)

    assert result =~ ~s[href="#fn-note"]
    assert result =~ ~s[<li id="fn-note">]
  end
end
