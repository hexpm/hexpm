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

    highlights = %{
      "diff-0-L0-1" =>
        ~s(<span class="l-variable">value</span> <span class="l-operator">=</span> &lt;script&gt;)
    }

    html =
      render_component(&DiffComponent.diff/1,
        diff: diff,
        id: "diff-0",
        highlights: highlights
      )

    assert html =~ "ghd-file-status-changed"
    assert html =~ "lib/app.ex"
    assert html =~ ~s(id="diff-0-L0-1")
    assert html =~ "class=\"l-variable\""
    assert html =~ "&lt;"
    refute html =~ "<script>"

    document = Floki.parse_document!(html)
    assert [_] = Floki.find(document, "div.ghd-file > button.ghd-file-header")
    assert [] = Floki.find(document, "details")

    assert Floki.attribute(document, "#diff-0-toggle", "aria-controls") == ["diff-0-body"]
    assert Floki.attribute(document, "#diff-0-toggle", "aria-expanded") == ["true"]

    assert [_] = Floki.find(document, ~s(.ghd-line-number[tabindex="0"][role="link"]))
    assert Floki.text(Floki.find(document, ".ghd-line-status")) == "+ "
    assert [_] = Floki.find(document, ".ghd-line-code")
  end

  test "renders added, removed, and oversized files" do
    for {from, to, status} <- [
          {nil, "new.txt", "added"},
          {"old.txt", nil, "removed"}
        ] do
      diff = %GitDiff.Patch{from: from, to: to, chunks: []}

      assert render_component(&DiffComponent.diff/1,
               diff: diff,
               id: status,
               highlights: %{}
             ) =~ status
    end

    oversized = render_component(&DiffComponent.too_large/1, file: "large.bin")
    assert oversized =~ "File is too large to be displayed (200 KB limit)."
    assert oversized =~ "unknown"
    assert oversized =~ "ghd-file-status-unknown"
    refute oversized =~ "ghd-file-status-too-large"
  end
end
