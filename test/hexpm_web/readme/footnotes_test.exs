defmodule HexpmWeb.Readme.FootnotesTest do
  use ExUnit.Case, async: true

  alias HexpmWeb.Readme.Sanitizer

  defp parse_footnotes(markdown) do
    {_status, ast, _messages} = Earmark.Parser.as_ast(markdown, gfm: true, footnotes: true)
    ast |> Earmark.transform() |> Sanitizer.sanitize()
  end

  describe "footnotes" do
    test "renders footnote reference as a link" do
      html = parse_footnotes("Text with a footnote[^1].\n\n[^1]: The footnote content.")

      assert html =~ ~s[<a href="#fn:1"]
      assert html =~ ~s[id="fnref:1"]
    end

    test "renders footnote definition with return link" do
      html = parse_footnotes("Text with a footnote[^1].\n\n[^1]: The footnote content.")

      assert html =~ ~s[id="fn:1"]
      assert html =~ ~s[href="#fnref:1"]
      assert html =~ "The footnote content."
    end

    test "preserves bidirectional anchor ids through sanitization" do
      html = parse_footnotes("See note[^1].\n\n[^1]: Note text.")

      assert html =~ ~s[id="fnref:1"]
      assert html =~ ~s[id="fn:1"]
    end
  end
end
