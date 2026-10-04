defmodule HexpmWeb.SyntaxHighlight.Output do
  @moduledoc """
  Checks that HTML from `lumis serve` has only what the html-linked formatter
  writes, since it is rendered as raw HTML and the process producing it parses
  untrusted source.

  The accepted tags are `<pre class="lumis">`, `<code class="language-*">`,
  `<div class="l-line" data-line="N">` and `<span class="l-*">`, each closed in
  order. Text between them cannot contain `<`. It is one pass over the HTML.
  """

  @spec valid?(binary()) :: boolean()
  def valid?(html) when is_binary(html), do: text(html, [])

  defp text(html, stack) do
    case :binary.match(html, "<") do
      :nomatch ->
        stack == []

      {position, 1} ->
        <<_text::binary-size(^position), "<", rest::binary>> = html
        tag(rest, stack)
    end
  end

  defp tag("/span>" <> rest, [:span | stack]), do: text(rest, stack)
  defp tag("/div>" <> rest, [:div | stack]), do: text(rest, stack)
  defp tag("/code>" <> rest, [:code | stack]), do: text(rest, stack)
  defp tag("/pre>" <> rest, [:pre | stack]), do: text(rest, stack)
  defp tag(~s(span class="l-) <> rest, stack), do: scope(rest, [:span | stack])
  defp tag(~s(div class="l-line" data-line=") <> rest, stack), do: line(rest, [:div | stack], 0)
  defp tag(~s(code class="language-) <> rest, stack), do: language(rest, [:code | stack], 0)
  defp tag(~s(pre class="lumis">) <> rest, stack), do: text(rest, [:pre | stack])
  defp tag(_rest, _stack), do: false

  defp scope(<<char, rest::binary>>, stack)
       when char in ?a..?z or char in ?0..?9 or char in [?_, ?-],
       do: scope(rest, stack)

  defp scope(~s(">) <> rest, stack), do: text(rest, stack)
  defp scope(_rest, _stack), do: false

  defp line(<<digit, rest::binary>>, stack, count) when digit in ?0..?9,
    do: line(rest, stack, count + 1)

  defp line(~s(">) <> rest, stack, count) when count > 0, do: text(rest, stack)
  defp line(_rest, _stack, _count), do: false

  defp language(<<char, rest::binary>>, stack, count)
       when char in ?a..?z or char in ?0..?9 or char == ?_,
       do: language(rest, stack, count + 1)

  defp language(~s(" translate="no" tabindex="0">) <> rest, stack, count) when count > 0,
    do: text(rest, stack)

  defp language(_rest, _stack, _count), do: false
end
