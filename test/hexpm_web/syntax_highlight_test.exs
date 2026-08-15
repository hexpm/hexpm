defmodule HexpmWeb.SyntaxHighlightTest do
  use ExUnit.Case, async: true

  alias HexpmWeb.SyntaxHighlight

  # Without this the assertions below race the highlighter's first load, and a
  # loaded machine loses: `highlight/3` gives up after @timeout and answers with
  # escaped plain source, which looks like a highlighting bug.
  setup do
    assert SyntaxHighlight.warm() == :ok
    :ok
  end

  test "highlights documents and line fragments with Lumis" do
    document = SyntaxHighlight.highlight("value = <script>", "lib/app.ex", "test document")

    assert document =~ ~s(class="lumis")
    assert document =~ ~s(class="l-variable")
    assert document =~ "&lt;"
    refute document =~ "<script>"

    assert [first, second] =
             SyntaxHighlight.highlight_lines(
               ["value = <script>", "IO.puts(value)"],
               "lib/app.ex",
               "test lines"
             )

    assert first =~ ~s(class="l-variable")
    assert first =~ "&lt;"
    assert second =~ "IO"
    refute first =~ "<pre"
  end

  @tag :capture_log
  test "uses escaped fallback output after timeout or failure" do
    assert ["&lt;script&gt;"] =
             SyntaxHighlight.run(
               fn -> Process.sleep(100) end,
               fn -> ["&lt;script&gt;"] end,
               "slow source",
               0
             )

    assert :fallback =
             SyntaxHighlight.run(
               fn -> raise "invalid source" end,
               fn -> :fallback end,
               "invalid source"
             )
  end
end
