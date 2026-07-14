defmodule HexpmWeb.DiffComponentTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias HexpmWeb.DiffComponent

  test "renders parsed patches through HEEx with highlighting and line anchors" do
    diff = %GitDiff.Patch{
      from: "lib/app.ex",
      to: "lib/app.ex",
      chunks: [
        %GitDiff.Chunk{
          header: "@@ -1 +1 @@",
          lines: [
            %GitDiff.Line{
              type: :add,
              from_line_number: "",
              to_line_number: 1,
              text: "+value = <script>"
            }
          ]
        }
      ]
    }

    html = render_component(&DiffComponent.diff/1, diff: diff, id: "diff-0")

    assert html =~ "ghd-file-status-changed"
    assert html =~ "lib/app.ex"
    assert html =~ ~s(id="#{:erlang.phash2({"lib/app.ex", "lib/app.ex"})}--1")
    assert html =~ "class=\"n\""
    assert html =~ "&lt;"
    refute html =~ "<script>"
  end

  test "renders added, removed, and oversized files" do
    for {from, to, status} <- [
          {nil, "new.txt", "added"},
          {"old.txt", nil, "removed"}
        ] do
      diff = %GitDiff.Patch{from: from, to: to, chunks: []}
      assert render_component(&DiffComponent.diff/1, diff: diff, id: status) =~ status
    end

    assert render_component(&DiffComponent.too_large/1, file: "large.bin") =~
             "CANNOT RENDER FILES LARGER THAN 1MB"
  end
end
