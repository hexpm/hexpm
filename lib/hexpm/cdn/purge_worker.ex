defmodule Hexpm.CDN.PurgeWorker do
  @moduledoc """
  Purges Fastly surrogate keys and verifies the purge took effect.

  A job purges its keys twice, two seconds apart, which is Fastly's own
  mitigation for the shield race (an edge refetching from the shield before
  the shield saw the purge). It then waits for propagation and checks every
  target the caller supplied against the CDN (`Hexpm.CDN.verify/2`: the
  nearest POP plus one probed POP per continent for the repository
  service). Targets still serving the old ETag anywhere mean the purge did
  not apply, so the keys are purged again and the targets rechecked, up to
  `:purge_verify_rounds` times, after which the job raises
  `Hexpm.CDN.PurgeVerificationError` and Oban retries it later.

  Purges queue up faster than they run during publish bursts, so on start a
  job absorbs the available jobs for the same service: their keys and
  targets are merged into this job's arguments (persisted, so a retry keeps
  them) and the absorbed jobs are cancelled. Fastly accepts up to 256 keys
  per purge request, so a job never carries more than that, and it looks at
  no more than 256 candidates, since each brings at least one key. Two
  targets for the same URL keep the later one's ETag, since that is the
  object the store holds now.

  The same object can also be written again after this job was enqueued,
  by a job this one did not absorb. That job's ETag is the one the CDN
  will serve, so a target that comes back stale is dropped, not re-purged,
  when a newer job for its URL exists.
  """

  use Oban.Worker, queue: :purge, max_attempts: 5

  import Ecto.Query, only: [from: 2]
  import Ecto.Changeset, only: [change: 2]

  alias Hexpm.CDN
  alias Hexpm.Repo

  require Logger

  @max_keys 256
  @max_targets 256

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(5)

  @impl Oban.Worker
  def perform(%Oban.Job{} = job) do
    %{"service" => service, "keys" => keys, "verify" => targets} = args = absorb_siblings(job)
    service = String.to_existing_atom(service)

    targets =
      targets
      |> dedupe_targets()
      |> Enum.map(&%{url: &1["url"], etag: &1["etag"], repository: &1["repository"]})

    metadata = %{
      service: service,
      keys: length(keys),
      targets: length(targets),
      absorbed: Map.get(args, "absorbed", 0)
    }

    :telemetry.span([:hexpm, :cdn, :purge], metadata, fn ->
      case purge_and_verify(job, service, keys, targets) do
        {:ok, rounds} ->
          Logger.info(
            "CDN_PURGE #{service} #{Enum.join(keys, " ")} verified=#{length(targets)} " <>
              "rounds=#{rounds} absorbed=#{metadata.absorbed} job=#{job.id}"
          )

          {:ok, Map.merge(metadata, %{result: :ok, rounds: rounds})}

        {:error, reason} ->
          {{:error, reason}, Map.merge(metadata, %{result: :error, rounds: 0})}
      end
    end)
  end

  defp purge_and_verify(job, service, keys, targets) do
    with :ok <- purge_twice(service, keys) do
      verify(job, service, keys, targets, 1)
    end
  end

  defp verify(_job, _service, _keys, [], _round), do: {:ok, 0}

  defp verify(job, service, keys, targets, round) do
    Process.sleep(config(:purge_verify_grace))

    stale =
      for {target, {:error, reason}} <- CDN.verify(service, targets),
          do: {target, reason}

    {superseded, stale} = Enum.split_with(stale, fn {target, _} -> superseded?(job, target) end)

    for {target, reason} <- superseded do
      Logger.info("CDN_PURGE_SUPERSEDED #{target.url} #{inspect(reason)} job=#{job.id}")
    end

    for {target, reason} <- stale do
      Logger.warning(
        "CDN_PURGE_STALE round=#{round} #{target.url} expected=#{inspect(target.etag)} " <>
          "#{inspect(reason)} keys=#{Enum.join(keys, " ")} job=#{job.id}"
      )
    end

    targets = targets -- Enum.map(superseded, &elem(&1, 0))

    cond do
      stale == [] ->
        {:ok, round}

      round < config(:purge_verify_rounds) ->
        with :ok <- purge_twice(service, keys) do
          verify(job, service, keys, targets, round + 1)
        end

      true ->
        raise Hexpm.CDN.PurgeVerificationError,
          service: service,
          keys: keys,
          stale: stale,
          rounds: round
    end
  end

  # A later job for the same URL, whether queued, running or done, carries
  # the ETag the store holds now; this job's expectation is out of date.
  defp superseded?(%Oban.Job{id: nil}, _target), do: false

  defp superseded?(%Oban.Job{id: id}, %{url: url}) do
    worker = Oban.Worker.to_string(__MODULE__)
    match = %{"verify" => [%{"url" => url}]}

    Repo.exists?(
      from(j in Oban.Job,
        where: j.worker == ^worker and j.id > ^id,
        where: j.state in ["scheduled", "available", "executing", "retryable", "completed"],
        where: fragment("? @> ?", j.args, ^match)
      )
    )
  end

  # Later targets replace earlier ones for the same URL: the running job's
  # own targets come first, absorbed jobs follow in id order.
  defp dedupe_targets(targets) do
    targets
    |> Enum.reverse()
    |> Enum.uniq_by(& &1["url"])
    |> Enum.reverse()
  end

  defp purge_twice(service, keys) do
    with :ok <- CDN.purge_key(service, keys) do
      Process.sleep(config(:purge_wait))
      CDN.purge_key(service, keys)
    end
  end

  # Merges the available jobs for the same service into this one. Runs in a
  # transaction: the siblings are row-locked so a concurrent job on another
  # node skips them, and this job's arguments are rewritten alongside the
  # cancellations so a later attempt still carries the absorbed keys.
  defp absorb_siblings(%Oban.Job{id: nil, args: args}), do: args

  defp absorb_siblings(%Oban.Job{id: id, args: %{"service" => service} = args} = job) do
    worker = Oban.Worker.to_string(__MODULE__)

    {:ok, args} =
      Repo.transaction(fn ->
        siblings =
          Repo.all(
            from(j in Oban.Job,
              where: j.worker == ^worker and j.state == "available" and j.id != ^id,
              where: fragment("?->>'service' = ?", j.args, ^service),
              order_by: j.id,
              limit: @max_keys,
              lock: "FOR UPDATE SKIP LOCKED"
            )
          )

        {args, absorbed} = merge(args, siblings)

        if absorbed == [] do
          args
        else
          {:ok, _} = Oban.cancel_all_jobs(from(j in Oban.Job, where: j.id in ^absorbed))
          job |> change(args: args) |> Repo.update!()
          args
        end
      end)

    args
  end

  defp merge(args, siblings) do
    Enum.reduce(siblings, {args, []}, fn sibling, {args, absorbed} ->
      keys = Enum.uniq(args["keys"] ++ sibling.args["keys"])
      verify = dedupe_targets(args["verify"] ++ sibling.args["verify"])

      if length(keys) > @max_keys or length(verify) > @max_targets do
        {args, absorbed}
      else
        args =
          args
          |> Map.put("keys", keys)
          |> Map.put("verify", verify)
          |> Map.update("absorbed", 1, &(&1 + 1))

        {args, [sibling.id | absorbed]}
      end
    end)
  end

  defp config(key), do: Application.fetch_env!(:hexpm, key)
end

defmodule Hexpm.CDN.PurgeVerificationError do
  defexception [:service, :keys, :stale, :rounds]

  @impl true
  def message(%{service: service, keys: keys, stale: stale, rounds: rounds}) do
    stale = Enum.map_join(stale, "\n", &describe/1)
    "purge of #{inspect(keys)} on #{service} not visible after #{rounds} rounds:\n#{stale}"
  end

  defp describe({target, {:stale, pops}}) do
    pops =
      Enum.map_join(pops, ", ", fn %{pop: pop, etag: etag, served_by: served_by} ->
        "#{pop} serves #{inspect(etag)} (#{served_by})"
      end)

    "  #{target.url} expected #{inspect(target.etag)}: #{pops}"
  end

  defp describe({target, reason}) do
    "  #{target.url} expected #{inspect(target.etag)}: #{inspect(reason)}"
  end
end
