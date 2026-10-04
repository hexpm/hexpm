defmodule HexpmWeb.SyntaxHighlightTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog
  import HexpmWeb.SyntaxHighlightHelpers

  alias HexpmWeb.SyntaxHighlight

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

  test "uses escaped plain source after a timeout" do
    source = slow_source(0.5) <> "<script>"

    log =
      capture_log(fn ->
        assert document =
                 SyntaxHighlight.highlight(source, "lib/app.ex", "slow source", timeout: 1)

        assert document =~ ~s(<div class="l-line" data-line="1">defmodule App do</div>)
        assert document =~ "&lt;script&gt;"
        refute document =~ "l-keyword"

        assert ["value = &lt;script&gt;"] =
                 SyntaxHighlight.highlight_lines(["value = <script>"], "lib/app.ex", "slow lines",
                   timeout: 0
                 )
      end)

    assert log =~ "Failed to highlight slow source: :timeout"
  end

  test "uses escaped plain source when highlighting is unavailable" do
    log =
      capture_log(fn ->
        assert SyntaxHighlight.highlight("<b>", "lib/app.ex", "source", name: :no_such_pool) ==
                 ~s(<pre class="lumis"><code><div class="l-line" data-line="1">&lt;b&gt;</div></code></pre>)
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
