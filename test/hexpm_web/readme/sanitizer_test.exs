defmodule HexpmWeb.Readme.SanitizerTest do
  use ExUnit.Case, async: true

  alias HexpmWeb.Readme.Sanitizer

  describe "sanitize/1" do
    test "allows safe tags" do
      html = "<p>Hello <strong>world</strong></p>"
      assert Sanitizer.sanitize(html) == html
    end

    test "strips disallowed tags but keeps content" do
      html = "<p>Hello <script>alert(1)</script> world</p>"
      assert Sanitizer.sanitize(html) == "<p>Hello alert(1) world</p>"
    end

    test "strips style tags" do
      html = "<p>Hello</p><style>body { color: red; }</style>"
      assert Sanitizer.sanitize(html) == "<p>Hello</p>body { color: red; }"
    end

    test "allows headings with id prefix" do
      html = ~s[<h2 id="installation">Installation</h2>]
      assert Sanitizer.sanitize(html) == ~s[<h2 id="user-content-installation">Installation</h2>]
    end

    test "allows links with safe href" do
      html = ~s[<a href="https://example.com">link</a>]
      result = Sanitizer.sanitize(html)
      assert result =~ ~s[href="https://example.com"]
      assert result =~ ~s[rel="nofollow noopener"]
      assert result =~ ~s[target="_blank"]
    end

    test "strips javascript: URLs from href" do
      html = ~s[<a href="javascript:void(0)">click</a>]
      result = Sanitizer.sanitize(html)
      refute result =~ "javascript"
      assert result =~ ~s[rel="nofollow noopener"]
    end

    test "strips data: URLs from href" do
      html = ~s[<a href="data:text/html,test">click</a>]
      result = Sanitizer.sanitize(html)
      refute result =~ ~s[href=]
    end

    test "strips javascript: URLs with control characters (WHATWG bypass)" do
      html = ~s[<a href="java\tscript:alert(1)">click</a>]
      result = Sanitizer.sanitize(html)
      refute result =~ ~s[href=]
    end

    test "allows mailto: URLs" do
      html = ~s[<a href="mailto:test@example.com">email</a>]
      result = Sanitizer.sanitize(html)
      assert result =~ ~s[href="mailto:test@example.com"]
    end

    test "allows relative href" do
      html = ~s[<a href="docs/guide.md">Guide</a>]
      result = Sanitizer.sanitize(html)
      assert result =~ ~s[href="docs/guide.md"]
    end

    test "strips javascript: URLs from img src" do
      html = ~s[<img src="javascript:void(0)">]
      result = Sanitizer.sanitize(html)
      refute result =~ "javascript"
    end

    test "allows img with safe attributes" do
      html = ~s[<img src="https://example.com/logo.png" alt="Logo" width="100" height="50">]
      result = Sanitizer.sanitize(html)
      assert result =~ ~s[src="https://example.com/logo.png"]
      assert result =~ ~s[alt="Logo"]
      assert result =~ ~s[width="100"]
    end

    test "strips event handlers" do
      html = ~s[<img src="x.png" onerror="alert(1)">]
      result = Sanitizer.sanitize(html)
      refute result =~ "onerror"
    end

    test "converts text-align style to align attribute on table cells" do
      html = ~s[<td style="text-align: center">data</td>]
      result = Sanitizer.sanitize(html)
      assert result =~ ~s[align="center"]
      refute result =~ "style"
    end

    test "strips non-text-align style from table cells" do
      html = ~s[<td style="background-color: red; color: blue">data</td>]
      result = Sanitizer.sanitize(html)
      refute result =~ "style"
      refute result =~ "align"
    end

    test "strips style attributes from non-table elements" do
      html = ~s[<p style="color: red">text</p>]
      result = Sanitizer.sanitize(html)
      refute result =~ "style"
    end

    test "allows code with class for syntax highlighting" do
      html = ~s[<code class="language-elixir">IO.puts("hello")</code>]
      assert Sanitizer.sanitize(html) =~ ~s[class="language-elixir"]
    end

    test "strips comments" do
      html = "<p>before</p><!-- comment --><p>after</p>"
      assert Sanitizer.sanitize(html) == "<p>before</p><p>after</p>"
    end

    test "allows task list checkboxes" do
      html = ~s[<input type="checkbox" checked disabled>]
      result = Sanitizer.sanitize(html)
      assert result =~ ~s[type="checkbox"]
      assert result =~ "checked"
      assert result =~ "disabled"
    end

    test "strips non-checkbox inputs" do
      html = ~s[<input type="text" value="phishing">]
      assert Sanitizer.sanitize(html) == ""
    end

    test "strips inputs without type" do
      html = ~s[<input value="phishing">]
      assert Sanitizer.sanitize(html) == ""
    end

    test "allows details/summary" do
      html = "<details><summary>Expand</summary><p>Content</p></details>"
      assert Sanitizer.sanitize(html) == html
    end

    test "allows definition lists" do
      html = "<dl><dt>Term</dt><dd>Definition</dd></dl>"
      assert Sanitizer.sanitize(html) == html
    end

    test "allows kbd tag" do
      html = "Press <kbd>Ctrl</kbd>+<kbd>C</kbd>"
      assert Sanitizer.sanitize(html) == html
    end

    test "allows table with align attribute" do
      html = ~s[<th align="center">Header</th>]
      assert Sanitizer.sanitize(html) == html
    end
  end
end
