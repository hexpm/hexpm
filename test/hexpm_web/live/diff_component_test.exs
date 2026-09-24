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

    document = LazyHTML.from_fragment(html)

    assert [_] =
             LazyHTML.query(document, "div.ghd-file > button.ghd-file-header") |> Enum.to_list()

    assert [] = LazyHTML.query(document, "details") |> Enum.to_list()

    assert LazyHTML.query(document, "#diff-0-toggle") |> LazyHTML.attribute("aria-controls") == [
             "diff-0-body"
           ]

    assert LazyHTML.query(document, "#diff-0-toggle") |> LazyHTML.attribute("aria-expanded") == [
             "true"
           ]

    assert [_] =
             LazyHTML.query(document, ~s(.ghd-line-number[tabindex="0"][role="link"]))
             |> Enum.to_list()

    assert LazyHTML.text(LazyHTML.query(document, ".ghd-line-status")) == "+ "
    assert [_] = LazyHTML.query(document, ".ghd-line-code") |> Enum.to_list()
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
    assert oversized =~ "File is too large to be displayed (100 KB limit)."
    assert oversized =~ "unknown"
    assert oversized =~ "ghd-file-status-unknown"
    refute oversized =~ "ghd-file-status-too-large"
  end

  test "renders renamed files with both paths" do
    diff = %GitDiff.Patch{from: "lib/old_name.ex", to: "lib/new_name.ex", chunks: []}

    html = render_component(&DiffComponent.diff/1, diff: diff, id: "renamed", highlights: %{})

    assert html =~ "ghd-file-status-renamed"
    assert html =~ "lib/old_name.ex → lib/new_name.ex"
  end
end
