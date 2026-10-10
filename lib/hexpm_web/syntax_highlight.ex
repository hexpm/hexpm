defmodule HexpmWeb.SyntaxHighlight do
  @moduledoc """
  Highlights file previews, diffs and README code blocks with lumis, in
  `lumis serve` processes from `HexpmWeb.SyntaxHighlight.Pool`.

  A highlight that runs past the budget's `:time_limit` comes back as plain
  text marked `data-lumis-budget="time"`. One that does not finish within the
  pool's `:timeout`, or fails, is shown as escaped plain text. A source that
  timed out or ended its process is shown as escaped plain text for an hour
  without being sent to the pool again, since each attempt would end another
  process.

  Every call emits `[:hexpm, :syntax_highlight, :start | :stop]` telemetry,
  with a `:result` of `:ok`, `:timeout`, `:queue_timeout`, `:exit`, `:error`,
  `:unavailable` or `:skipped` on stop.
  """

  use GenServer
  require Logger

  alias HexpmWeb.SyntaxHighlight.Pool

  @budget [time_limit: 300, match_limit: 4096]
  @skip_ttl :timer.hours(1)

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, name, name: name)
  end

  def budget, do: @budget

  @doc """
  Highlights `source` as an html-linked document.

  Options are `:budget`, which defaults to `budget/0`, `:table`, the name this
  module was started with, and those of `HexpmWeb.SyntaxHighlight.Pool.highlight/4`.
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
    {table, opts} = Keyword.pop(opts, :table, __MODULE__)
    digest = :crypto.hash(:sha256, :erlang.term_to_binary({kind, language, source}))

    :telemetry.span([:hexpm, :syntax_highlight], %{}, fn ->
      if skipped?(table, digest) do
        {:error, %{result: :skipped}}
      else
        case Pool.highlight(kind, source, language, budget ++ opts) do
          {:ok, result} ->
            {{:ok, result}, %{result: :ok}}

          {:error, reason} ->
            if ended_process?(reason) do
              :ets.insert(table, {digest, System.monotonic_time(:millisecond) + @skip_ttl})
            end

            Logger.warning("Failed to highlight #{label}: #{inspect(reason)}")
            {:error, %{result: result(reason)}}
        end
      end
    end)
  end

  defp ended_process?(:timeout), do: true
  defp ended_process?({:exit, _status}), do: true
  defp ended_process?(_reason), do: false

  defp result({:exit, _status}), do: :exit
  defp result({:lumis, _message}), do: :error
  defp result(:malformed_reply), do: :error
  defp result(reason), do: reason

  defp skipped?(table, digest) do
    case :ets.lookup(table, digest) do
      [{^digest, expires_at}] -> expires_at > System.monotonic_time(:millisecond)
      [] -> false
    end
  end

  @impl true
  def init(table) do
    :ets.new(table, [:named_table, :public, :set, write_concurrency: true])
    schedule_sweep()
    {:ok, table}
  end

  @impl true
  def handle_info(:sweep, table) do
    now = System.monotonic_time(:millisecond)
    :ets.select_delete(table, [{{:_, :"$1"}, [{:<, :"$1", now}], [true]}])
    schedule_sweep()
    {:noreply, table}
  end

  defp schedule_sweep() do
    Process.send_after(self(), :sweep, @skip_ttl)
  end

  # The markup lumis writes for plain text.
  defp plain_source(source) do
    lines =
      source
      |> String.replace(~r/\r?\n\z/, "")
      |> String.split(["\r\n", "\n"])
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
