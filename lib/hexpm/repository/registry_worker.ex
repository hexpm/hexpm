defmodule Hexpm.Repository.RegistryWorker do
  @moduledoc """
  Rebuilds registry objects in the background and purges them from the CDN.

  Jobs come in four types: `package` (one `packages/<name>` object),
  `package_delete`, `repository` (`names` and `versions`) and `full`. A job
  runs the build in a transaction that holds the `:registry` advisory lock,
  so builds never interleave across nodes, and enqueues the CDN purge inside
  that transaction, so the purge is only visible once the write is committed
  and never runs while the lock is held. A job waits `:registry_lock_wait`
  milliseconds for the lock and snoozes when it does not get it, so a build
  queued behind a long full build neither holds a connection for minutes nor
  spends its attempts on waiting.

  Builds read the database when they run rather than carrying a change with
  them, so queued jobs are consolidated before the read, inside the
  transaction: a `package` job takes over the other queued `package` jobs
  of its repository (up to `@batch`) and builds all of them with one round
  of queries and one purge; a `full` job cancels every queued job of its
  repository, since it rewrites everything they would; `repository` and
  `package_delete` jobs cancel queued jobs with the same arguments. A job whose insert commits
  after the cancel is left alone and picks up whatever that job's
  transaction wrote, and a failed build rolls the cancellations back. This
  is what keeps a burst of publishes from queueing one `names` and
  `versions` rebuild per release, and an advisory that touches a hundred
  packages from building them one job at a time.
  """

  use Oban.Worker, queue: :registry, max_attempts: 5

  import Ecto.Query, only: [dynamic: 2, from: 2]

  alias Hexpm.Repo
  alias Hexpm.Repository.{Package, RegistryBuilder, Repository}

  require Logger

  @lock_snooze 30
  @batch 100

  @impl Oban.Worker
  def timeout(%Oban.Job{args: %{"type" => "full"}}), do: :timer.minutes(30)
  def timeout(_job), do: :timer.minutes(5)

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"type" => type}} = job) do
    metadata = %{type: String.to_existing_atom(type)}

    :telemetry.span([:hexpm, :registry_builder, :build], metadata, fn ->
      result = build(job)
      {result, Map.put(metadata, :result, result_tag(result))}
    end)
  end

  @doc "Enqueues a rebuild of the package's registry object."
  def enqueue_package(%Package{} = package), do: insert(package_args(package), 0)

  @doc "Enqueues removal of the package's registry object."
  def enqueue_package_delete(%Package{} = package) do
    package = Repo.preload(package, :repository)

    insert(
      %{
        "type" => "package_delete",
        "repository_id" => package.repository.id,
        "name" => package.name
      },
      0
    )
  end

  @doc "Enqueues a rebuild of the repository's `names` and `versions`."
  def enqueue_repository(%Repository{id: id}) do
    insert(%{"type" => "repository", "repository_id" => id}, 1)
  end

  @doc "Enqueues a rebuild of every registry object of the repository."
  def enqueue_full(%Repository{id: id}) do
    insert(%{"type" => "full", "repository_id" => id}, 2)
  end

  defp package_args(%Package{id: id}), do: %{"type" => "package", "package_id" => id}

  defp insert(args, priority) do
    args |> new(priority: priority) |> Oban.insert()
  end

  defp build(%Oban.Job{} = job) do
    Repo.transaction(
      fn ->
        lock_registry(job)

        with {:ok, work, consolidated} <- consolidate(job),
             {:ok, purges} <- run(work) do
          keys = Enum.flat_map(purges, & &1.keys)
          verify = Enum.flat_map(purges, & &1.verify)
          if keys != [], do: Hexpm.CDN.purge(:fastly_hexrepo, keys, verify: verify)
          log(job, "built", consolidated)
          :ok
        else
          {:discard, reason} ->
            log(job, "skipped, #{reason}", 0)
            {:discard, reason}
        end
      end,
      timeout: timeout(job)
    )
    |> case do
      {:ok, result} -> result
    end
  rescue
    error in Postgrex.Error ->
      case error do
        %{postgres: %{code: :lock_not_available}} -> {:snooze, @lock_snooze}
        _other -> reraise error, __STACKTRACE__
      end
  end

  # lock_timeout is a session setting; SET LOCAL scopes it to this
  # transaction, and it takes an integer of milliseconds.
  defp lock_registry(job) do
    wait = Application.fetch_env!(:hexpm, :registry_lock_wait)
    Repo.query!("SET LOCAL lock_timeout = #{wait}", [], timeout: timeout(job))
    Repo.advisory_xact_lock(:registry, timeout: timeout(job))
  end

  defp run({:packages, repository_id, ids}) do
    with {:ok, repository} <- repository(repository_id) do
      packages =
        Repo.all(
          from(p in Package,
            where: p.id in ^ids and p.repository_id == ^repository_id,
            order_by: p.id
          )
        )

      {:ok, if(packages == [], do: [], else: [RegistryBuilder.packages(repository, packages)])}
    end
  end

  # A package published again under the name after the delete was queued
  # owns the object now; deleting it would undo that build.
  defp run({:package_delete, repository_id, name}) do
    with {:ok, repository} <- repository(repository_id) do
      exists =
        Repo.exists?(
          from(p in Package, where: p.repository_id == ^repository_id and p.name == ^name)
        )

      {:ok, if(exists, do: [], else: [RegistryBuilder.package_delete(repository, name)])}
    end
  end

  defp run({:repository, repository_id}) do
    with {:ok, repository} <- repository(repository_id) do
      {:ok, [RegistryBuilder.repository(repository)]}
    end
  end

  defp run({:full, repository_id}) do
    with {:ok, repository} <- repository(repository_id) do
      {:ok, [RegistryBuilder.full(repository)]}
    end
  end

  defp repository(id) do
    case Repo.get(Repository, id) do
      nil -> {:discard, :repository_not_found}
      repository -> {:ok, repository}
    end
  end

  # Returns what to build and how many queued jobs this one took over, or
  # a discard when the job's subject is gone.
  defp consolidate(%Oban.Job{args: %{"type" => "package", "package_id" => id}} = job) do
    case Repo.get(Package, id) do
      nil ->
        {:discard, :package_not_found}

      %Package{repository_id: repository_id} ->
        repository_packages =
          from(p in Package, where: p.repository_id == ^repository_id, select: p.id)

        siblings =
          siblings(
            job,
            dynamic(
              [j],
              fragment("?->>'type' = 'package'", j.args) and
                fragment("(?->>'package_id')::bigint", j.args) in subquery(repository_packages)
            ),
            @batch
          )

        ids = Enum.uniq([id | Enum.map(siblings, & &1.args["package_id"])])
        {:ok, {:packages, repository_id, ids}, cancel(siblings)}
    end
  end

  defp consolidate(%Oban.Job{args: %{"type" => "full", "repository_id" => id}} = job) do
    package_ids = from(p in Package, where: p.repository_id == ^id, select: p.id)

    siblings =
      siblings(
        job,
        dynamic(
          [j],
          fragment("(?->>'repository_id')::bigint", j.args) == ^id or
            fragment("(?->>'package_id')::bigint", j.args) in subquery(package_ids)
        ),
        nil
      )

    {:ok, {:full, id}, cancel(siblings)}
  end

  defp consolidate(%Oban.Job{args: %{"type" => "repository", "repository_id" => id}} = job) do
    {:ok, {:repository, id}, cancel(same_args(job))}
  end

  defp consolidate(
         %Oban.Job{args: %{"type" => "package_delete", "repository_id" => id, "name" => name}} =
           job
       ) do
    {:ok, {:package_delete, id, name}, cancel(same_args(job))}
  end

  defp same_args(%Oban.Job{args: args} = job) do
    siblings(job, dynamic([j], j.args == ^args), nil)
  end

  # Queued jobs of this worker matching `filter`, row-locked so a job on
  # another node that consolidates at the same time skips them.
  defp siblings(%Oban.Job{id: nil}, _filter, _limit), do: []

  defp siblings(%Oban.Job{id: id}, filter, limit) do
    worker = Oban.Worker.to_string(__MODULE__)

    query =
      from(j in Oban.Job,
        where: j.worker == ^worker and j.state == "available" and j.id != ^id,
        where: ^filter,
        order_by: j.id,
        lock: "FOR UPDATE SKIP LOCKED"
      )

    query = if limit, do: from(j in query, limit: ^limit), else: query
    Repo.all(query)
  end

  defp cancel(siblings) do
    siblings
    |> Enum.map(& &1.id)
    |> Enum.chunk_every(1000)
    |> Enum.reduce(0, fn ids, count ->
      {:ok, cancelled} = Oban.cancel_all_jobs(from(j in Oban.Job, where: j.id in ^ids))
      count + cancelled
    end)
  end

  defp log(%Oban.Job{id: id, args: args}, what, cancelled) do
    Logger.info(
      "REGISTRY_BUILDER #{args["type"]} #{what} job=#{id} args=#{inspect(args)} " <>
        "consolidated=#{cancelled}"
    )
  end

  defp result_tag(:ok), do: :ok
  defp result_tag({:discard, _}), do: :discard
  defp result_tag({:snooze, _}), do: :snooze
end
