defmodule HexpmWeb.Readme.RendererTest do
  use ExUnit.Case, async: true

  alias HexpmWeb.Readme.Renderer

  defp render(content) do
    Renderer.render("hexpm", "README.md", content, "my_package", "1.0.0")
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

  test "invalid UTF-8 bytes are replaced with the replacement character" do
    content = "the \x91simple form\x92 that is used by Xmerl"

    result = render(content)

    assert result =~ "the �simple form� that is used by Xmerl"
  end

  test "invalid UTF-8 bytes in plain text readmes are replaced" do
    content = "caf\xE9 au lait"

    result = Renderer.render("hexpm", "README", content, "my_package", "1.0.0")

    assert result =~ "<pre>caf� au lait</pre>"
  end
end
