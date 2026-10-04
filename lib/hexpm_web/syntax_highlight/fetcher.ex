defmodule HexpmWeb.SyntaxHighlight.Fetcher do
  @moduledoc """
  Downloads parsers `lumis serve` did not have, one language at a time, with
  `lumis languages cache` into the data directory the workers read. Workers
  find a language there on their next request.

  The download runs outside the sandbox, because it needs the network, and is
  only ever given language names from the lumis catalog, never package source.
  It gets the same empty environment as the workers.

  A language that failed is not tried again for an hour.
  """

  use GenServer

  require Logger

  alias HexpmWeb.SyntaxHighlight.Launcher

  # Each of the two downloads has a 30 s timeout in lumis, and either may be
  # tried on a second CDN.
  @timeout 180_000
  @retry_after 3_600_000

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @doc """
  Queues `languages` to be downloaded unless they are queued or failed within
  the hour.
  """
  def fetch(fetcher \\ __MODULE__, languages) do
    GenServer.cast(fetcher, {:fetch, languages})
  end

  @impl true
  def init(opts) do
    {:ok,
     %{
       data_dir: Keyword.get_lazy(opts, :data_dir, &Lumis.Port.data_dir/0),
       queue: :queue.new(),
       queued: MapSet.new(),
       running: nil,
       failed: %{}
     }}
  end

  @impl true
  def handle_cast({:fetch, languages}, state) do
    now = System.monotonic_time(:millisecond)

    state =
      languages
      |> Enum.reject(&(&1 in state.queued or recently_failed?(state, &1, now)))
      |> Enum.reduce(state, fn language, state ->
        %{
          state
          | queue: :queue.in(language, state.queue),
            queued: MapSet.put(state.queued, language)
        }
      end)

    {:noreply, start_next(state)}
  end

  @impl true
  def handle_info({ref, result}, %{running: {language, %Task{ref: ref}, timer}} = state) do
    Process.demonitor(ref, [:flush])
    Process.cancel_timer(timer)

    case result do
      :ok ->
        {:noreply, finish(state, language, :ok)}

      {:error, output} ->
        Logger.warning("Failed to download the #{language} parser: #{output}")
        {:noreply, finish(state, language, :error)}
    end
  end

  def handle_info(
        {:DOWN, ref, _, _, reason},
        %{running: {language, %Task{ref: ref}, timer}} = state
      ) do
    Process.cancel_timer(timer)
    Logger.warning("Failed to download the #{language} parser: #{inspect(reason)}")
    {:noreply, finish(state, language, :error)}
  end

  def handle_info({:timeout, ref}, %{running: {language, %Task{ref: ref} = task, _timer}} = state) do
    Task.shutdown(task, :brutal_kill)
    Logger.warning("Downloading the #{language} parser took over #{@timeout} ms")
    {:noreply, finish(state, language, :error)}
  end

  def handle_info(_message, state) do
    {:noreply, state}
  end

  defp recently_failed?(state, language, now) do
    case state.failed do
      %{^language => failed_at} -> now - failed_at < @retry_after
      %{} -> false
    end
  end

  defp finish(state, language, result) do
    failed =
      case result do
        :ok -> Map.delete(state.failed, language)
        :error -> Map.put(state.failed, language, System.monotonic_time(:millisecond))
      end

    start_next(%{
      state
      | running: nil,
        queued: MapSet.delete(state.queued, language),
        failed: failed
    })
  end

  defp start_next(%{running: nil} = state) do
    case :queue.out(state.queue) do
      {{:value, language}, queue} ->
        data_dir = state.data_dir

        task =
          Task.Supervisor.async_nolink(Hexpm.Tasks, fn ->
            Lumis.Port.cache([language], data_dir: data_dir, env: Launcher.env())
          end)

        timer = Process.send_after(self(), {:timeout, task.ref}, @timeout)
        %{state | queue: queue, running: {language, task, timer}}

      {:empty, _queue} ->
        state
    end
  end

  defp start_next(state), do: state
end
