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

  test "highlights a long Elixir operator chain within the timeout" do
    chain = Enum.map_join(1..500, " or ", &"x === #{&1}")
    source = "defmodule M do\n  def f(x) when #{chain} do\n    x\n  end\nend\n"

    assert SyntaxHighlight.highlight(source, "lib/chain.ex", "test chain") =~
             ~s(class="l-keyword")
  end

  @tag :capture_log
  test "answers the fallback after the task times out or fails" do
    assert ["&lt;script&gt;"] =
             SyntaxHighlight.run(
               make_ref(),
               fn -> Process.sleep(100) end,
               fn -> ["&lt;script&gt;"] end,
               "slow source",
               timeout: 0
             )

    assert :fallback =
             SyntaxHighlight.run(
               make_ref(),
               fn -> raise "invalid source" end,
               fn -> :fallback end,
               "invalid source"
             )
  end

  @tag :capture_log
  test "uses escaped fallback output after timeout or failure" do
    lines = List.duplicate("value = <script>", 2_000)
    opts = [budget: [time_limit: 1, match_limit: 4096]]

    document = SyntaxHighlight.highlight(Enum.join(lines, "\n"), "lib/app.ex", "slow", opts)

    assert document =~ ~s(data-lumis-budget="time")
    assert document =~ "&lt;script&gt;"
    refute document =~ ~s(class="l-variable")

    assert SyntaxHighlight.highlight_lines(lines, "lib/app.ex", "slow", opts) |> Enum.uniq() ==
             ["value = &lt;script&gt;"]

    error = %Lumis.RenderError{reason: :runtime, detail: "unavailable"}
    assert :fallback = SyntaxHighlight.or_plain({:error, error}, "invalid", fn -> :fallback end)
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

  describe "limits" do
    setup do
      table = :"#{__MODULE__}.#{System.unique_integer([:positive])}"
      start_supervised!({SyntaxHighlight, name: table})
      %{table: table}
    end

    @tag :capture_log
    test "skips a source that ran out of time", %{table: table} do
      key = make_ref()
      test = self()

      blocked = fn ->
        send(test, {:blocked, self()})

        receive do
          :release -> :done
        end
      end

      assert :fallback =
               SyntaxHighlight.run(
                 key,
                 blocked,
                 fn -> :fallback end,
                 "slow source",
                 table: table,
                 timeout: 0
               )

      assert_receive {:blocked, pid}

      assert :fallback =
               SyntaxHighlight.run(
                 key,
                 fn -> send(test, :ran) end,
                 fn -> :fallback end,
                 "slow source",
                 table: table
               )

      refute_received :ran

      assert :ran =
               SyntaxHighlight.run(
                 make_ref(),
                 fn -> send(test, :ran) end,
                 fn -> :fallback end,
                 "other source",
                 table: table
               )

      ref = Process.monitor(pid)
      send(pid, :release)
      assert_receive {:DOWN, ^ref, :process, ^pid, _reason}
    end

    @tag :capture_log
    test "falls back to the markup Lumis renders for plain text", %{table: table} do
      for source <- ["one\n\n<three>\n", "", "a\r\n\r\nb", ~s(q "x" & y's)] do
        opts = [table: table, max_concurrency: 0]

        assert SyntaxHighlight.highlight(source, "lib/app.ex", "test fallback", opts) ==
                 Lumis.highlight!(source, formatter: {:html_linked, language: "plaintext"})
      end
    end

    @tag :capture_log
    test "falls back without starting work while every slot is taken", %{table: table} do
      test = self()
      opts = [table: table, max_concurrency: 1]

      blocked = fn ->
        send(test, {:blocked, self()})

        receive do
          :release -> :done
        end
      end

      assert :fallback =
               SyntaxHighlight.run(
                 make_ref(),
                 blocked,
                 fn -> :fallback end,
                 "blocked",
                 Keyword.put(opts, :timeout, 0)
               )

      assert_receive {:blocked, pid}

      assert :fallback =
               SyntaxHighlight.run(
                 make_ref(),
                 fn -> send(test, :ran) end,
                 fn -> :fallback end,
                 "waiting",
                 opts
               )

      refute_received :ran

      ref = Process.monitor(pid)
      send(pid, :release)
      assert_receive {:DOWN, ^ref, :process, ^pid, _reason}

      assert :ran =
               SyntaxHighlight.run(
                 make_ref(),
                 fn -> send(test, :ran) end,
                 fn -> :fallback end,
                 "after release",
                 opts
               )
    end
  end
end
