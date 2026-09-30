defmodule HexpmWeb.SyntaxHighlightTest do
  use ExUnit.Case, async: true

  alias HexpmWeb.SyntaxHighlight

  setup_all do
    Lumis.Languages.load(["elixir"])
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
    lines = List.duplicate("value = <script>", 2_000)
    budget = [time_limit: 1, match_limit: 4096]

    document = SyntaxHighlight.highlight(Enum.join(lines, "\n"), "lib/app.ex", "slow", budget)

    assert document =~ ~s(data-lumis-budget="time")
    assert document =~ "&lt;script&gt;"
    refute document =~ ~s(class="l-variable")

    assert SyntaxHighlight.highlight_lines(lines, "lib/app.ex", "slow", budget) |> Enum.uniq() ==
             ["value = &lt;script&gt;"]

    error = %Lumis.RenderError{reason: :runtime, detail: "unavailable"}
    assert :fallback = SyntaxHighlight.or_plain({:error, error}, "invalid", fn -> :fallback end)
  end

  # VHDL is in the Lumis catalog but hexpm does not depend on its parser.
  test "renders plain text when the parser is not installed" do
    lines = ["signal clk : std_logic;", "end architecture;"]
    document = SyntaxHighlight.highlight(Enum.join(lines, "\n"), "vhdl", "missing parser")

    assert document =~ "signal clk : std_logic;"
    refute document =~ ~r/class="l-(?!line)/
  end

  test "keeps one fragment per diff line, including trailing blank lines" do
    assert SyntaxHighlight.highlight_lines([""], "elixir", "blank lines") == [""]

    assert [_value, ""] =
             SyntaxHighlight.highlight_lines(["value = 1", ""], "elixir", "blank lines")

    assert SyntaxHighlight.highlight_lines(["", "x", "", ""], "vhdl", "blank lines") ==
             ["", "x", "", ""]
  end
end
