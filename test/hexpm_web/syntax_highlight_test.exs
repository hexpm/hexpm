defmodule HexpmWeb.SyntaxHighlightTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog
  import HexpmWeb.SyntaxHighlightHelpers

  alias HexpmWeb.SyntaxHighlight
  alias HexpmWeb.SyntaxHighlight.Pool

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

  test "highlights a long Elixir operator chain within the timeout" do
    chain = Enum.map_join(1..500, " or ", &"x === #{&1}")
    source = "defmodule M do\n  def f(x) when #{chain} do\n    x\n  end\nend\n"

    assert SyntaxHighlight.highlight(source, "lib/chain.ex", "test chain") =~
             ~s(class="l-keyword")
  end

  test "returns plain text marked with the budget after the time limit" do
    lines = List.duplicate("value = <script>", 2_000)
    opts = [budget: [time_limit: 1, match_limit: 4096]]

    document = SyntaxHighlight.highlight(Enum.join(lines, "\n"), "lib/app.ex", "slow", opts)

    assert document =~ ~s(data-lumis-budget="time")
    assert document =~ "&lt;script&gt;"
    refute document =~ ~s(class="l-variable")

    assert SyntaxHighlight.highlight_lines(lines, "lib/app.ex", "slow", opts) |> Enum.uniq() ==
             ["value = &lt;script&gt;"]
  end

  test "preserves diff lines when the highlighting match limit is exhausted" do
    lines = ["fn main() {", "  let value = (1 + (2 * (3 - 4)));", "}", ""]
    opts = [budget: [time_limit: 0, match_limit: 1]]

    document = SyntaxHighlight.highlight(Enum.join(lines, "\n"), "rust", "matches", opts)
    assert document =~ ~s(data-lumis-budget="matches")

    highlighted = SyntaxHighlight.highlight_lines(lines, "rust", "matches", opts)
    assert length(highlighted) == length(lines)

    assert Enum.map(highlighted, fn html ->
             html |> LazyHTML.from_fragment() |> LazyHTML.text()
           end) == lines
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

  test "uses escaped plain source after a timeout, and skips that source afterwards" do
    # A timeout closes a process, and the other tests would wait for the pool
    # to load every language into its replacement.
    pool = :"#{inspect(__MODULE__)} timeout"
    table = :"#{inspect(__MODULE__)} skipped"
    start_supervised!({Pool, name: pool, workers: 1})
    start_supervised!({SyntaxHighlight, name: table})
    assert await_idle(pool)

    opts = [name: pool, table: table]
    source = slow_source(0.5) <> "<script>"
    ref = :telemetry_test.attach_event_handlers(self(), [[:hexpm, :syntax_highlight, :stop]])

    log =
      capture_log(fn ->
        assert document =
                 SyntaxHighlight.highlight(
                   source,
                   "lib/app.ex",
                   "slow source",
                   [timeout: 1] ++ opts
                 )

        assert document =~ ~s(<span class="l-line" data-line="1">defmodule App do</span>)
        assert document =~ "&lt;script&gt;"
        refute document =~ "l-keyword"

        assert await_idle(pool)
        [os_pid] = idle_os_pids(pool)

        assert SyntaxHighlight.highlight(source, "lib/app.ex", "slow source", opts) == document
        assert_receive {[:hexpm, :syntax_highlight, :stop], ^ref, _, %{result: :skipped}}
        assert idle_os_pids(pool) == [os_pid]

        assert ["value = &lt;script&gt;"] =
                 SyntaxHighlight.highlight_lines(
                   ["value = <script>"],
                   "lib/app.ex",
                   "slow lines",
                   [timeout: 0] ++ opts
                 )
      end)

    assert log =~ "Failed to highlight slow source: :timeout"
  end

  test "uses the markup lumis writes for plain text when highlighting is unavailable" do
    sources = [
      "",
      "\n",
      "<b>",
      "a & 'b' \"c\"",
      "a\n<b>",
      "a\n<b>\n",
      "a\n\n",
      "one\n\n<three>\n",
      "a\r\n\r\nb",
      "a\r\n"
    ]

    log =
      capture_log(fn ->
        for source <- sources do
          assert SyntaxHighlight.highlight(source, "lib/app.ex", "source", name: :no_such_pool) ==
                   Lumis.highlight!(source, formatter: {:html_linked, language: "plaintext"})
        end
      end)

    assert log =~ "Failed to highlight source: :unavailable"
  end

  test "emits telemetry with the result" do
    ref = :telemetry_test.attach_event_handlers(self(), [[:hexpm, :syntax_highlight, :stop]])

    SyntaxHighlight.highlight(":ok", "lib/app.ex", "source")
    assert_receive {[:hexpm, :syntax_highlight, :stop], ^ref, %{duration: _}, %{result: :ok}}

    capture_log(fn ->
      SyntaxHighlight.highlight(":ok", "lib/app.ex", "source", name: :no_such_pool)
    end)

    assert_receive {[:hexpm, :syntax_highlight, :stop], ^ref, _, %{result: :unavailable}}
  end
end
