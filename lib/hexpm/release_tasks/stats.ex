defmodule Hexpm.ReleaseTasks.Stats do
  require Logger
  import Ecto.Query, only: [from: 2]
  alias Hexpm.{Repo, Store, Utils}

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

  def run(date \\ Utils.utc_yesterday(), dryrun? \\ false) do
    {time, size} =
      :timer.tc(fn ->
        do_run(date, dryrun?)
      end)

    Logger.info("[stats] completed #{size} downloads (#{div(time, 1000)}ms)")
  end

  def do_run(date, dryrun?) do
    :ets.new(@ets, [:named_table, :public])

    try do
      process_buckets(date)
      repositories = repositories()
      packages = packages()
      releases = releases()

      # May not be a perfect count since it counts downloads without a release
      # in the database. Should be uncommon
      num = ets_stream() |> Enum.reduce(0, fn {_, count}, acc -> count + acc end)

      unless dryrun? do
        Repo.transaction(
          fn ->
            Repo.delete_all(from(d in Download, where: d.day == ^date))

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

            Repo.refresh_view(PackageDownload)
            Repo.refresh_view(ReleaseDownload)
          end,
          timeout: 120_000
        )
      end

      num
    after
      :ets.delete(@ets)
    end
  catch
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
    prefix = "fastly_hex/#{date}"
    keys = Store.list(bucket, prefix) |> Enum.to_list()
    process_keys(bucket, keys)
  end

  defp process_keys(bucket, keys) do
    Task.async_stream(
      keys,
      fn key ->
        Store.get(bucket, key, [])
        |> maybe_unzip(key)
        |> process_file()
      end,
      max_concurrency: 10,
      timeout: 600_000
    )
    |> Stream.run()
  end

  defp process_file(file) do
    lines = String.split(file, "\n")

    Enum.each(lines, fn line ->
      case parse_line(line) do
        {repository, package, version} ->
          key = {repository, package, version}
          :ets.update_counter(@ets, key, 1, {key, 0})

        nil ->
          :ok
      end
    end)
  end

  defp parse_line(line) do
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

  defp maybe_unzip(data, key) do
    if String.ends_with?(key, ".gz") do
      :zlib.gunzip(data)
    else
      data
    end
  end

  defp nillify(""), do: nil
  defp nillify(binary), do: binary

  defp copy(nil), do: nil
  defp copy(binary), do: :binary.copy(binary)
end
