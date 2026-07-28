defmodule Hexpm.Oban.Pruner do
  @moduledoc """
  Prunes finished Oban jobs, keeping the ones that failed for longer.

  `Oban.Plugins.Pruner` takes one age for every finished state, so keeping a
  failure around long enough to audit means keeping every successful job for
  just as long. Successes are the bulk of the table and nobody reads them:
  hexpm completes around eight thousand jobs a day and discards twenty.

  That matters because Oban's queue length metric counts the whole table on a
  timer, from every node. Against thirty days of completed jobs that is a
  sequential scan of a hundred and seventy megabytes, and it was the single
  largest consumer of database time on the instance.
  """

  @behaviour Oban.Plugin

  use GenServer

  import Ecto.Query, only: [where: 3, or_where: 3, limit: 2, select: 2, join: 5]

  alias Oban.{Job, Peer, Plugin, Repo, Validation}

  require Logger

  defstruct [
    :conf,
    :timer,
    interval: :timer.seconds(30),
    limit: 10_000,
    max_age: :timer.hours(24 * 3) |> div(1000),
    discarded_max_age: :timer.hours(24 * 365) |> div(1000)
  ]

  @doc false
  @spec child_spec(Keyword.t()) :: Supervisor.child_spec()
  def child_spec(opts), do: super(opts)

  @impl Plugin
  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name)

    GenServer.start_link(__MODULE__, struct!(__MODULE__, opts), name: name)
  end

  @impl Plugin
  def validate(opts) do
    Validation.validate_schema(opts,
      conf: :any,
      name: :any,
      interval: :pos_integer,
      limit: :pos_integer,
      max_age: :pos_integer,
      discarded_max_age: :pos_integer
    )
  end

  @impl Plugin
  def format_logger_output(_conf, meta), do: Map.take(meta, [:pruned_count])

  @impl GenServer
  def init(state) do
    Process.flag(:trap_exit, true)

    :telemetry.execute([:oban, :plugin, :init], %{}, %{conf: state.conf, plugin: __MODULE__})

    {:ok, schedule_prune(state)}
  end

  @impl GenServer
  def terminate(_reason, state) do
    if is_reference(state.timer), do: Process.cancel_timer(state.timer)

    :ok
  end

  @impl GenServer
  def handle_info(:prune, %__MODULE__{} = state) do
    meta = %{conf: state.conf, plugin: __MODULE__}

    :telemetry.span([:oban, :plugin], meta, fn ->
      case prune(state) do
        {:ok, extra} when is_map(extra) -> {:ok, Map.merge(meta, extra)}
        error -> {:error, Map.put(meta, :error, error)}
      end
    end)

    {:noreply, schedule_prune(state)}
  end

  def handle_info(message, state) do
    Logger.warning("Hexpm.Oban.Pruner received an unexpected message: #{inspect(message)}")

    {:noreply, state}
  end

  defp schedule_prune(state) do
    %{state | timer: Process.send_after(self(), :prune, state.interval)}
  end

  defp prune(state) do
    if Peer.leader?(state.conf) do
      Repo.transaction(state.conf, fn -> prune_jobs(state) end, on_exhausted: :log)
    else
      {:ok, %{pruned_count: 0, pruned_succeeded: 0, pruned_failed: 0}}
    end
  end

  @doc false
  def prune_jobs(%__MODULE__{} = state) do
    # Oban ages each state by the column it sets on entering it, and a completed
    # job's is scheduled_at rather than a completed_at.
    succeeded =
      delete(state, state.max_age, fn query, cutoff ->
        query
        |> where([j], j.state == "completed" and j.scheduled_at < ^cutoff)
        |> or_where([j], j.state == "cancelled" and j.cancelled_at < ^cutoff)
      end)

    failed =
      delete(state, state.discarded_max_age, fn query, cutoff ->
        where(query, [j], j.state == "discarded" and j.discarded_at < ^cutoff)
      end)

    %{pruned_count: succeeded + failed, pruned_succeeded: succeeded, pruned_failed: failed}
  end

  # Deleting through a limited subquery keeps a backlog from turning into one
  # statement that runs past the query timeout.
  defp delete(state, max_age, filter) do
    cutoff = DateTime.add(DateTime.utc_now(), -max_age)

    subquery =
      Job
      |> select([:id])
      |> filter.(cutoff)
      |> where([j], not is_nil(j.queue))
      |> limit(^state.limit)

    query = join(Job, :inner, [j], x in subquery(subquery), on: j.id == x.id)

    {count, _} = Repo.delete_all(state.conf, query)

    count
  end
end
