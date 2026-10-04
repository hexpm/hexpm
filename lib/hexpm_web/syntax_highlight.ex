defmodule HexpmWeb.SyntaxHighlight do
  @moduledoc """
  Highlights file previews and diffs with lumis, in `lumis serve` processes
  from `HexpmWeb.SyntaxHighlight.Pool`. Anything that does not highlight in
  time, or at all, is shown as escaped plain text.

  Every call emits `[:hexpm, :syntax_highlight, :start | :stop]` telemetry,
  with a `:result` of `:ok`, `:not_cached`, `:timeout`, `:queue_timeout`,
  `:exit`, `:error`, `:rejected_output` or `:unavailable` on stop.
  """

  require Logger

  alias HexpmWeb.SyntaxHighlight.Pool

  @line_pattern ~r/<div class="l-line" data-line="\d+">(.*?)\n?<\/div>/s

  def highlight(source, language, label, opts \\ []) do
    case run(source, language, label, opts) do
      {:ok, html} -> html
      :error -> plain_source(source)
    end
  end

  def highlight_lines(lines, language, label, opts \\ [])

  def highlight_lines([], _language, _label, _opts), do: []

  def highlight_lines(lines, language, label, opts) when is_list(lines) do
    with {:ok, html} <- run(Enum.join(lines, "\n"), language, label, opts),
         fragments = Regex.scan(@line_pattern, html, capture: :all_but_first),
         true <- length(fragments) == length(lines) do
      List.flatten(fragments)
    else
      false ->
        Logger.warning("Lumis returned a different number of lines for #{label}")
        Enum.map(lines, &escape/1)

      :error ->
        Enum.map(lines, &escape/1)
    end
  end

  defp run(source, language, label, opts) do
    :telemetry.span([:hexpm, :syntax_highlight], %{}, fn ->
      case Pool.highlight(source, language, opts) do
        {:ok, html} ->
          {{:ok, html}, %{result: :ok}}

        {:error, :not_cached} ->
          {:error, %{result: :not_cached}}

        {:error, reason} ->
          Logger.warning("Failed to highlight #{label}: #{inspect(reason)}")
          {:error, %{result: result(reason)}}
      end
    end)
  end

  defp result({:exit, _status}), do: :exit
  defp result({:lumis, _message}), do: :error
  defp result(reason), do: reason

  defp plain_source(source) do
    lines =
      source
      |> String.split("\n")
      |> Enum.with_index(1)
      |> Enum.map_join(fn {line, number} ->
        ~s(<div class="l-line" data-line="#{number}">#{escape(line)}</div>)
      end)

    ~s(<pre class="lumis"><code>#{lines}</code></pre>)
  end

  defp escape(source) do
    source
    |> Phoenix.HTML.html_escape()
    |> Phoenix.HTML.safe_to_string()
  end
end
