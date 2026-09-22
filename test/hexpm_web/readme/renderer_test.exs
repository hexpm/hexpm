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

  test "preserves whitespace between highlighted tokens" do
    code = "def add(left, right) do\n  left + right\nend\n"
    document = render("```elixir\n" <> code <> "```\n") |> LazyHTML.from_fragment()

    assert [_code] = LazyHTML.query(document, "pre code") |> Enum.to_list()
    assert Enum.count(LazyHTML.query(document, "pre code span")) > 1
    assert document |> LazyHTML.query("pre code") |> LazyHTML.text() == code
  end

  test "preserves whitespace-only nodes between code spans" do
    content =
      ~s|<pre><code><span class="l-name">one</span> \t<span class="l-name">two</span>\n\n<span class="l-name">three</span></code></pre>|

    document = render(content) |> LazyHTML.from_fragment()

    assert Enum.count(LazyHTML.query(document, "pre code span")) == 3
    assert document |> LazyHTML.query("pre code") |> LazyHTML.text() == "one \ttwo\n\nthree"
  end

  test "preserves whitespace between inline elements" do
    content = ~s|<p><em>one</em> \t<strong>two</strong>\n<a href="guide.md">three</a></p>|
    document = render(content) |> LazyHTML.from_fragment()

    assert Enum.count(LazyHTML.query(document, "p > em, p > strong, p > a")) == 3
    assert document |> LazyHTML.query("p") |> LazyHTML.text() == "one \ttwo\nthree"
  end

  test "preserves blank lines in highlighted and unhighlighted code blocks" do
    code = "first = 1\n\n\nsecond = 2\n"

    for language <- ["", "elixir"] do
      document = render("```#{language}\n#{code}```\n") |> LazyHTML.from_fragment()

      assert [_code] = LazyHTML.query(document, "pre code") |> Enum.to_list()
      assert document |> LazyHTML.query("pre code") |> LazyHTML.text() == code
    end
  end

  test "preserves leading blank lines in raw pre blocks after reparsing" do
    for {content, expected} <- [
          {"<pre>\ntext</pre>", "text"},
          {"<pre>\n\ntext</pre>", "\ntext"},
          {"<pre>\n\n\ntext</pre>", "\n\ntext"},
          {"<pre>\n\n<span>text</span></pre>", "\ntext"},
          {"<div><pre>&#10;&#10;text</pre></div>", "\ntext"},
          {"<pre>\n\n</pre>", "\n"},
          {"<pre><code>\n\ntext</code></pre>", "\n\ntext"},
          {"<pre>\n<!-- comment -->\ntext</pre>", "\ntext"},
          {"<pre><span></span>\ntext</pre>", "\ntext"}
        ] do
      document = render(content) |> LazyHTML.from_document()

      assert [pre] = LazyHTML.query(document, "pre") |> Enum.to_list()
      assert LazyHTML.text(pre) == expected, "unexpected text for #{inspect(content)}"
    end
  end

  test "preserves leading newlines in plain text readmes after reparsing" do
    for filename <- ["README", "README.txt"],
        content <- ["\n  Plain text\n", "\n\n  Plain text\n\n", "\n\n", "\r\nPlain text\r\n"] do
      document =
        Renderer.render("hexpm", filename, content, "my_package", "1.0.0")
        |> LazyHTML.from_document()

      assert [pre] = LazyHTML.query(document, "pre") |> Enum.to_list()
      assert LazyHTML.text(pre) == String.replace(content, "\r\n", "\n")
    end
  end

  test "escapes literal HTML in plain text readmes" do
    content = ~s|<img src="logo.png" onerror="alert(1)"> & <script>alert('x')</script>|
    result = Renderer.render("hexpm", "README.txt", content, "my_package", "1.0.0")

    assert result ==
             "<pre>&lt;img src=&quot;logo.png&quot; onerror=&quot;alert(1)&quot;&gt; &amp; &lt;script&gt;alert(&#39;x&#39;)&lt;/script&gt;</pre>"

    document = LazyHTML.from_fragment(result)
    assert [{"pre", [], [^content]}] = LazyHTML.to_tree(document)
    assert [] = LazyHTML.query(document, "img, script") |> Enum.to_list()
  end

  test "renders complete tables with alignment attributes" do
    content = """
    | Left | Center | Right |
    | :--- | :----: | ----: |
    | one  | two    | three |
    | four | five   | six   |
    """

    document = render(content) |> LazyHTML.from_fragment()

    assert [_table] = LazyHTML.query(document, "table") |> Enum.to_list()
    assert [_header] = LazyHTML.query(document, "table > thead > tr") |> Enum.to_list()
    assert Enum.count(LazyHTML.query(document, "table > tbody > tr")) == 2

    headers = LazyHTML.query(document, "table > thead > tr > th")
    cells = LazyHTML.query(document, "table > tbody > tr > td")
    assert Enum.map(headers, &LazyHTML.text/1) == ["Left", "Center", "Right"]
    assert Enum.map(cells, &LazyHTML.text/1) == ["one", "two", "three", "four", "five", "six"]
    assert LazyHTML.attribute(headers, "align") == ["left", "center", "right"]

    assert LazyHTML.attribute(cells, "align") == [
             "left",
             "center",
             "right",
             "left",
             "center",
             "right"
           ]

    assert [] = LazyHTML.query(document, "[style]") |> Enum.to_list()
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
