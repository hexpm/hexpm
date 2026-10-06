defmodule HexpmWeb.SyntaxHighlight do
  @moduledoc """
  Highlights file previews, diffs and README code blocks with lumis, in
  `lumis serve` processes from `HexpmWeb.SyntaxHighlight.Pool`.

  A highlight that runs past the budget's `:time_limit` comes back as plain
  text marked `data-lumis-budget="time"`. One that does not finish within the
  pool's `:timeout`, or fails, is shown as escaped plain text.

  Every call emits `[:hexpm, :syntax_highlight, :start | :stop]` telemetry,
  with a `:result` of `:ok`, `:timeout`, `:queue_timeout`, `:exit`, `:error` or
  `:unavailable` on stop.
  """

  require Logger

  alias HexpmWeb.SyntaxHighlight.Pool

  @budget [time_limit: 300, match_limit: 4096]

  def budget, do: @budget

  @doc """
  Highlights `source` as an html-linked document.

  Options are `:budget`, which defaults to `budget/0`, and those of
  `HexpmWeb.SyntaxHighlight.Pool.highlight/4`.
  """
  def highlight(source, language, label, opts \\ []) do
    case run(:document, source, language, label, opts) do
      {:ok, html} -> html
      :error -> plain_source(source)
    end
  end

  @doc """
  Highlights `lines` as one html-linked fragment per line, taking the same
  options as `highlight/4`.
  """
  def highlight_lines(lines, language, label, opts \\ [])

  def highlight_lines([], _language, _label, _opts), do: []

  def highlight_lines(lines, language, label, opts) when is_list(lines) do
    case run(:lines, Enum.map_join(lines, &(&1 <> "\n")), language, label, opts) do
      {:ok, fragments} -> fragments
      :error -> Enum.map(lines, &escape/1)
    end
  end

  defp run(kind, source, language, label, opts) do
    {budget, opts} = Keyword.pop(opts, :budget, @budget)

    :telemetry.span([:hexpm, :syntax_highlight], %{}, fn ->
      case Pool.highlight(kind, source, language, budget ++ opts) do
        {:ok, result} ->
          {{:ok, result}, %{result: :ok}}

        {:error, reason} ->
          Logger.warning("Failed to highlight #{label}: #{inspect(reason)}")
          {:error, %{result: result(reason)}}
      end
    end)
  end

  defp result({:exit, _status}), do: :exit
  defp result({:lumis, _message}), do: :error
  defp result(:malformed_reply), do: :error
  defp result(reason), do: reason

  # The markup lumis writes for plain text. A final newline ends the last line
  # rather than starting another.
  defp plain_source(source) do
    lines =
      case String.split(source, "\n") do
        [_ | [_ | _]] = lines when binary_part(source, byte_size(source), -1) == "\n" ->
          Enum.drop(lines, -1)

        lines ->
          lines
      end

    lines =
      lines
      |> Enum.with_index(1)
      |> Enum.map_join("\n", fn {line, number} ->
        ~s(<span class="l-line" data-line="#{number}">#{escape(line)}</span>)
      end)

    ~s(<pre class="lumis"><code class="language-plaintext" translate="no" tabindex="0">) <>
      lines <> "</code></pre>"
  end

  defp escape(source) do
    source
    |> Phoenix.HTML.html_escape()
    |> Phoenix.HTML.safe_to_string()
  end
end
