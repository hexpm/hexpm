defmodule HexpmWeb.SyntaxHighlightTest do
  use ExUnit.Case, async: false

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

  @tag :capture_log
  test "uses escaped fallback output after timeout or failure" do
    supervisor = start_supervised!({Task.Supervisor, max_children: 1})

    assert ["&lt;script&gt;"] =
             SyntaxHighlight.run(
               fn -> Process.sleep(100) end,
               fn -> ["&lt;script&gt;"] end,
               "slow source",
               0,
               supervisor
             )

    assert :fallback =
             SyntaxHighlight.run(
               fn -> raise "invalid source" end,
               fn -> :fallback end,
               "invalid source",
               1_000,
               supervisor
             )
  end

  @tag :capture_log
  test "uses escaped fallback output when all highlighting slots are occupied" do
    supervisor = start_supervised!({Task.Supervisor, max_children: 1})
    owner = self()

    {:ok, task} =
      Task.Supervisor.start_child(supervisor, fn ->
        send(owner, :started)
        receive do: (:stop -> :ok)
      end)

    assert_receive :started

    assert :fallback =
             SyntaxHighlight.run(
               fn -> :highlighted end,
               fn -> :fallback end,
               "busy source",
               100,
               supervisor
             )

    send(task, :stop)
  end

  test "uses escaped fallback output over the byte and line limits" do
    config = Application.fetch_env!(:hexpm, SyntaxHighlight)
    large = String.duplicate("<", config[:max_size] + 1)
    many_lines = List.duplicate("<", config[:max_lines] + 1)

    assert SyntaxHighlight.highlight(large, "large.txt", "large source") ==
             "<pre class=\"lumis\"><code><div class=\"l-line\" data-line=\"1\">" <>
               String.duplicate("&lt;", config[:max_size] + 1) <>
               "</div></code></pre>"

    assert SyntaxHighlight.highlight_lines(many_lines, "many-lines.txt", "many lines") ==
             List.duplicate("&lt;", config[:max_lines] + 1)
  end
end
