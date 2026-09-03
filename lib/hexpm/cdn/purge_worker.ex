defmodule Hexpm.CDN.PurgeWorker do
  @moduledoc """
  Purges Fastly surrogate keys and verifies the purge took effect.

  A job purges its keys twice, two seconds apart, which is Fastly's own
  mitigation for the shield race (an edge refetching from the shield before
  the shield saw the purge). It then waits for propagation and checks every
  target the caller supplied against the CDN (`Hexpm.CDN.verify/2`: the
  nearest POP plus one probed POP per continent for the repository
  service). A target whose copy anywhere is older than the write means the
  purge did not apply, so the keys are purged again and the targets
  rechecked, up to `:purge_verify_rounds` times, after which the job raises
  `Hexpm.CDN.PurgeVerificationError` and Oban retries it later.

  Purges queue up faster than they run during publish bursts, so on start a
  job absorbs the available jobs for the same service: their keys and
  targets are merged into this job's arguments (persisted, so a retry keeps
  them) and the absorbed jobs are cancelled. Fastly accepts up to 256 keys
  per purge request, so a job never carries more than that, and it looks at
  no more than 256 candidates, since each brings at least one key. Two
  targets for the same URL keep the one with the higher write number, since
  that is the object the store holds now.

  The same object can also be written again after this job was enqueued,
  by a job this one did not absorb. The check compares write numbers, so
  the CDN serving that later write passes this job's target too, and the
  later job verifies its own. When the number cannot decide, because the
  copy served carries none or the object has been deleted since, a newer
  job for the URL settles it: the target is dropped and that job's check
  covers the URL.
  """

  use Oban.Worker, queue: :purge, max_attempts: 5

  import Ecto.Query, only: [from: 2]
  import Ecto.Changeset, only: [change: 2]

  alias Hexpm.CDN
  alias Hexpm.CDN.PurgeVerificationError
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
      |> Enum.map(
        &%{url: &1["url"], etag: &1["etag"], write: &1["write"], repository: &1["repository"]}
      )

    metadata = %{
      service: service,
      keys: length(keys),
      targets: length(targets),
      absorbed: Map.get(args, "absorbed", 0)
    }

    :telemetry.span([:hexpm, :cdn, :purge], metadata, fn ->
      case purge_and_verify(job, service, keys, targets) do
        {:ok, rounds} ->
          Logger.info(%{
            message: "CDN_PURGE #{service} #{Enum.join(keys, " ")} verified",
            service: service,
            keys: keys,
            verified: length(targets),
            rounds: rounds,
            absorbed: metadata.absorbed,
            job_id: job.id
          })

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

    {superseded, stale} =
      Enum.split_with(stale, fn {target, reason} ->
        undecided?(target, reason) and superseded?(job, target)
      end)

    for {target, reason} <- superseded do
      Logger.info(%{
        message: "CDN_PURGE_SUPERSEDED #{target.url}",
        url: target.url,
        reason: inspect(reason),
        job_id: job.id
      })
    end

    targets = targets -- Enum.map(superseded, &elem(&1, 0))

    for {target, reason} <- stale do
      Logger.warning(%{
        message: "CDN_PURGE_STALE #{target.url}",
        round: round,
        url: target.url,
        expected: PurgeVerificationError.expected(target),
        reason: inspect(reason),
        keys: keys,
        job_id: job.id
      })
    end

    cond do
      stale == [] ->
        {:ok, round}

      round < config(:purge_verify_rounds) ->
        with :ok <- purge_twice(service, keys) do
          verify(job, service, keys, targets, round + 1)
        end

      true ->
        raise PurgeVerificationError,
          service: service,
          keys: keys,
          stale: stale,
          rounds: round
    end
  end

  # The write number decides when the copy carries one. A copy without one
  # is judged by ETag, and a 404 or redirect for a target that expected
  # content may be a deletion since the write; neither tells whether a
  # later write explains it.
  defp undecided?(_target, {:stale, pops}),
    do: Enum.all?(pops, &match?(%{served: {:etag, _}}, &1))

  defp undecided?(%{etag: etag}, {:status, status, _cache})
       when is_binary(etag) and status in [301, 404],
       do: true

  defp undecided?(_target, _reason), do: false

  # A later job for the same URL, whether queued, running or done, carries
  # what the store holds now; its check covers the URL.
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

  # One target per URL, the one with the highest write number; between
  # equals (or targets without one) the later wins.
  defp dedupe_targets(targets) do
    targets
    |> Enum.with_index()
    |> Enum.sort_by(fn {target, index} -> {target["write"] || 0, index} end, :desc)
    |> Enum.uniq_by(fn {target, _index} -> target["url"] end)
    |> Enum.sort_by(fn {_target, index} -> index end)
    |> Enum.map(fn {target, _index} -> target end)
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

  @doc "Describes what the check wanted for `target`, for logs and this message."
  def expected(%{etag: nil}), do: "404"
  def expected(%{etag: _etag, write: write}) when is_integer(write), do: "write #{write}"
  def expected(%{etag: etag}), do: inspect(etag)

  defp describe({target, {:stale, pops}}) do
    pops =
      Enum.map_join(pops, ", ", fn %{pop: pop, served: served, cache: cache} ->
        "#{pop} serves #{served(served)} (#{cache})"
      end)

    "  #{target.url} expected #{expected(target)}: #{pops}"
  end

  defp describe({target, reason}) do
    "  #{target.url} expected #{expected(target)}: #{inspect(reason)}"
  end

  defp served({:write, nil}), do: "no write number"
  defp served({:write, write}), do: "write #{write}"
  defp served({:etag, etag}), do: inspect(etag)
end
