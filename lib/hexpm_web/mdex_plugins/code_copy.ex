defmodule HexpmWeb.MDExPlugins.CodeCopy do
  @moduledoc """
  Wraps fenced and indented code blocks with a copy control.

  The control reuses the existing `CopyButton` script. The text placed on the
  clipboard is the code block's source (`literal`), not the highlighted HTML
  and not the markdown fences.
  """

  @doc """
  `MDEx.traverse_and_update/3` callback that wraps each `MDEx.CodeBlock`.

  The accumulator is the next unique id index. Start at `1`.
  """
  def transform(%MDEx.CodeBlock{} = node, index) do
    {wrap_with_copy_control(node, "markdown-code-#{index}"), index + 1}
  end

  def transform(node, index), do: {node, index}

  defp wrap_with_copy_control(%MDEx.CodeBlock{literal: source} = node, id) do
    highlighted =
      node
      |> MDEx.Document.wrap()
      |> MDEx.to_html!(syntax_highlight: [formatter: :html_linked])
      |> String.trim()

    escaped_source =
      source
      |> Phoenix.HTML.html_escape()
      |> Phoenix.HTML.safe_to_string()

    icon_html =
      HexpmWeb.ViewIcons.icon(:heroicon, "square-2-stack", class: "size-4")
      |> Phoenix.HTML.safe_to_string()

    %MDEx.HtmlBlock{
      literal: """
      <div id="#{id}" class="markdown-code-block relative" data-value="#{escaped_source}">
      <button type="button" id="#{id}-copy" phx-hook="CopyButton" data-copy-target="#{id}" class="absolute top-2 right-2 z-10 size-8 flex items-center justify-center rounded bg-grey-800 text-grey-200 hover:bg-grey-700 dark:bg-grey-900 dark:hover:bg-grey-600" aria-label="Copy" title="Copy">
      #{icon_html}
      </button>
      #{highlighted}
      </div>
      """
    }
  end
end
