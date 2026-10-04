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

  test "highlights a long Elixir operator chain within the timeout" do
    chain = Enum.map_join(1..500, " or ", &"x === #{&1}")
    source = "defmodule M do\n  def f(x) when #{chain} do\n    x\n  end\nend\n"

    assert SyntaxHighlight.highlight(source, "lib/chain.ex", "test chain") =~
             ~s(class="l-keyword")
  end

  @tag :capture_log
  test "uses escaped fallback output after timeout or failure" do
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

      assert :fallback =
               SyntaxHighlight.run(
                 key,
                 fn -> Process.sleep(100) end,
                 fn -> :fallback end,
                 "slow source",
                 table: table,
                 timeout: 0
               )

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
