defmodule Hexpm.Repository.DownloadsWorker do
  use Oban.Worker,
    queue: :heavy,
    max_attempts: 5,
    unique: [
      period: :infinity,
      states: :incomplete,
      fields: [:worker]
    ]

  require Logger
  import Ecto.Query, only: [from: 2]
  alias Hexpm.{CronMonitor, Repo, Store, Utils}

  alias Hexpm.Repository.{
    Download,
    Package,
    PackageDownload,
    Release,
    ReleaseDownload,
    Repository
  }

  @fastly_regex ~r<
    [^\040]+\040 # syslog
    [^\040]+\040 # user
    [^\040]+\040 # source
    [^\040]+\040 # IP address
    (?:(?:"[^"]+")|(?:\[[^\]]+\]))\040 # time
    "GET\040/
    (?:repos/([^/]+)/)? # repository
    tarballs/
    ([^-]+) # package
    -
    ([\d\w\.\-]+) # version
    .tar
    (?:\?[^\040"]*)?
    (?:\040HTTP/\d\.\d)?
    "\040
    ([0-9]{3})\040 # status
  >x

  @ets __MODULE__
  @max_line_bytes 1_048_576
  @count_batch_lines 5_000
  @task_timeout 3_600_000
  @monitor_slug "hexpm-stats"
  @monitor_schedule "0 1 * * *"

  @impl Oban.Worker
  def timeout(_job), do: 3_600_000

  @impl Oban.Worker
  def perform(job) do
    case date(job) do
      {:ok, date} ->
        CronMonitor.run(@monitor_slug, @monitor_schedule, fn -> run(date) end)

      {:error, reason} ->
        {:cancel, reason}
    end
  end

  def run(date \\ Utils.utc_yesterday(), dryrun? \\ false) do
    {time, size} =
      :timer.tc(fn ->
        do_run(date, dryrun?)
      end)

    Logger.info(%{
      message: "Download stats completed",
      event: "stats.completed",
      downloads: size,
      duration_us: time
    })
  end

  def do_run(date, dryrun?) do
    :ets.new(@ets, [:named_table, :public, write_concurrency: true])

    try do
      {repositories, packages, releases} =
        time_log("collects stats", fn ->
          process_buckets(date)
          repositories = repositories()
          packages = packages()
          releases = releases()
          {repositories, packages, releases}
        end)

      # May not be a perfect count since it counts downloads without a release
      # in the database. Should be uncommon
      num = ets_stream() |> Enum.reduce(0, fn {_, count}, acc -> count + acc end)

      expect_downloads? = Application.fetch_env!(:hexpm, :stats_expect_downloads)

      if num == 0 and not dryrun? and expect_downloads? do
        raise "[stats] no downloads found for #{date}"
      end

      unless dryrun? do
        Repo.transaction(
          fn ->
            time_log("delete downloads", fn ->
              Repo.delete_all(from(d in Download, where: d.day == ^date))
            end)

            time_log("insert downloads", fn ->
              ets_stream()
              |> Stream.flat_map(fn {{repository, package, version}, count} ->
                repository_id = repositories[repository]
                package_id = packages[{repository_id, package}]

                if release_id = releases[{package_id, version}] do
                  [%{package_id: package_id, release_id: release_id, downloads: count, day: date}]
                else
                  []
                end
              end)
              |> Stream.chunk_every(1000, 1000, [])
              |> Enum.each(&Repo.insert_all(Download, &1))
            end)

            # Scoped to this transaction; the default 4MB makes the view
            # aggregations over the downloads table spill to disk
            Repo.query!("SET LOCAL work_mem = '128MB'")

            time_log("refresh PackageDownload view", fn ->
              Repo.refresh_view(PackageDownload, timeout: 60_000)
            end)

            time_log("refresh ReleaseDownload view", fn ->
              Repo.refresh_view(ReleaseDownload, timeout: 60_000)
            end)
          end,
          timeout: 600_000
        )

        vacuum_downloads()
      end

      num
    after
      :ets.delete(@ets)
    end
  rescue
    exception ->
      Logger.error("[stats] failed")
      reraise exception, __STACKTRACE__
  end

  def ets_stream() do
    start_fun = fn -> :ets.first(@ets) end
    after_fun = fn _ -> :ok end

    next_fun = fn
      :"$end_of_table" -> {:halt, nil}
      key -> {:ets.lookup(@ets, key), :ets.next(@ets, key)}
    end

    Stream.resource(start_fun, next_fun, after_fun)
  end

  defp process_buckets(date) do
    bucket = Application.get_env(:hexpm, :logs_bucket)
    prefix = "fastly_hex/dt=#{date}/"
    keys = Store.list(bucket, prefix) |> Enum.to_list()
    process_keys(bucket, keys)
  end

  defp process_keys(bucket, keys) do
    Hexpm.Tasks
    |> Task.Supervisor.async_stream_nolink(keys, &process_key(bucket, &1),
      max_concurrency: 10,
      timeout: @task_timeout
    )
    |> Enum.each(fn
      {:ok, _result} ->
        :ok

      {:exit, {exception, stacktrace}} when is_exception(exception) ->
        reraise exception, stacktrace

      {:exit, reason} ->
        exit(reason)
    end)
  end

  defp process_key(bucket, key) do
    case Store.stream(bucket, key) do
      nil ->
        raise "#{key} is gone from the logs bucket"

      chunks ->
        chunks
        |> gunzip(key)
        |> lines()
        |> Stream.chunk_every(@count_batch_lines)
        |> Task.async_stream(fn batch -> Enum.each(batch, &count/1) end,
          max_concurrency: System.schedulers_online(),
          ordered: false,
          timeout: @task_timeout
        )
        |> Stream.run()
    end
  end

  # inflateEnd runs only when the input ended, where it raises data_error for
  # a truncated object; on any other exit the original exception stays.
  defp gunzip(chunks, key) do
    if String.ends_with?(key, ".gz") do
      Stream.transform(
        chunks,
        fn ->
          z = :zlib.open()
          :ok = :zlib.inflateInit(z, 31, :reset)
          z
        end,
        fn chunk, z -> {inflate(z, chunk), z} end,
        fn z ->
          :zlib.inflateEnd(z)
          {[], z}
        end,
        fn z -> :zlib.close(z) end
      )
    else
      chunks
    end
  end

  # safeInflate returns a bounded piece of output per call, so a chunk that
  # expands a thousandfold is still handled a piece at a time.
  defp inflate(z, chunk) do
    Stream.unfold({:input, chunk}, fn
      :done -> nil
      {:input, data} -> inflated(:zlib.safeInflate(z, data))
      :more -> inflated(:zlib.safeInflate(z, []))
    end)
  end

  defp inflated({:continue, output}), do: {IO.iodata_to_binary(output), :more}
  defp inflated({:finished, output}), do: {IO.iodata_to_binary(output), :done}

  defp lines(chunks) do
    Stream.transform(
      chunks,
      fn -> "" end,
      fn chunk, carry ->
        {carry, complete} = List.pop_at(String.split(carry <> chunk, "\n"), -1)

        if byte_size(carry) > @max_line_bytes do
          raise "[stats] a log line is longer than #{@max_line_bytes} bytes"
        end

        {complete, carry}
      end,
      fn
        "" -> {[], ""}
        carry -> {[carry], ""}
      end,
      fn _carry -> :ok end
    )
  end

  defp count(line) do
    case parse_line(line) do
      {_repository, _package, _version} = key -> :ets.update_counter(@ets, key, 1, {key, 0})
      nil -> :ok
    end
  end

  def parse_line(line) do
    case Regex.run(@fastly_regex, line) do
      [_, repository, package, version, status] when status in ~w(200 304) ->
        {copy(nillify(repository)) || "hexpm", copy(package), copy(version)}

      _ ->
        nil
    end
  end

  defp repositories() do
    from(r in Repository, select: {r.name, r.id})
    |> Repo.all()
    |> Map.new()
  end

  defp packages() do
    from(p in Package, select: {{p.repository_id, p.name}, p.id})
    |> Repo.all()
    |> Map.new()
  end

  defp releases() do
    from(r in Release, select: {{r.package_id, r.version}, r.id})
    |> Repo.all()
    |> Map.new(fn {{pid, vsn}, rid} -> {{pid, to_string(vsn)}, rid} end)
  end

  defp nillify(""), do: nil
  defp nillify(binary), do: binary

  defp copy(nil), do: nil
  defp copy(binary), do: :binary.copy(binary)

  # Runs outside the transaction above, which VACUUM cannot run inside. This job
  # is the only writer, so nothing else sets the visibility map bits the day's
  # new pages need, and nothing else refreshes the day histogram that every read
  # of this table filters on. Autovacuum does not reach it either: its insert
  # threshold scales with the table, and this one is 43M rows and growing.
  @doc false
  def vacuum_downloads() do
    if Application.get_env(:hexpm, :skip_maintenance_vacuum, false) do
      :ok
    else
      time_log("vacuum downloads", fn ->
        Repo.query!("VACUUM (ANALYZE) downloads", [], timeout: 600_000)
      end)

      :ok
    end
  end

  defp time_log(action, fun) do
    {time, result} = :timer.tc(fun)

    Logger.info(%{
      message: "Download stats step completed",
      event: "stats.step",
      step: action,
      duration_us: time
    })

    result
  end

  defp date(%Oban.Job{args: args, scheduled_at: scheduled_at}) when map_size(args) == 0 do
    case scheduled_at do
      %DateTime{} -> {:ok, scheduled_at |> DateTime.to_date() |> Date.add(-1)}
      _other -> {:error, :missing_scheduled_at}
    end
  end

  defp date(%Oban.Job{args: %{"date" => date} = args})
       when map_size(args) == 1 and is_binary(date) do
    case Date.from_iso8601(date) do
      {:ok, date} -> {:ok, date}
      {:error, _reason} -> {:error, {:invalid_date, date}}
    end
  end

  defp date(%Oban.Job{args: %{"date" => date} = args}) when map_size(args) == 1,
    do: {:error, {:invalid_date, date}}

  defp date(%Oban.Job{args: args}), do: {:error, {:invalid_args, args}}
end
