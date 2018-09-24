defmodule Hexpm.ReleaseTasks.Stats do
  require Logger
  import Ecto.Query, only: [from: 2]
  alias Hexpm.{Repo, Store, Utils}

  alias Hexpm.Accounts.Organization

  alias Hexpm.Repository.{
    Download,
    Package,
    PackageDownload,
    Release,
    ReleaseDownload
  }

  @fastly_regex ~r<
    [^\040]+\040 # syslog
    [^\040]+\040 # user
    [^\040]+\040 # source
    [^\040]+\040 # IP address
    (?:(?:"[^"]+")|(?:\[[^\]]+\]))\040 # time
    "GET\040/
    (?:([^/]+)/)? # repository
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

  def run() do
    buckets =
      Application.get_env(:hexpm, :logs_buckets)
      |> String.split(";")
      |> Enum.map(&String.split(&1, ","))

    try do
      {time, size} =
        :timer.tc(fn ->
          run(Utils.utc_yesterday(), buckets)
        end)

      Logger.info("[stats] completed #{size} downloads (#{div(time, 1000)}ms)")
    catch
      exception ->
        stacktrace = System.stacktrace()
        Logger.error("[stats] failed")
        reraise exception, stacktrace
    end
  end

  @doc false
  def run(date, buckets, dryrun? \\ false) do
    fastly_prefix = "fastly_hex/#{date}"
    formats = [{fastly_prefix, @fastly_regex}]

    :ets.new(@ets, [:named_table, :public])

    try do
      process_buckets(buckets, formats)
      organizations = organizations()
      packages = packages()
      releases = releases()

      # May not be a perfect count since it counts downloads without a release
      # in the database. Should be uncommon
      num = @ets |> ets_stream() |> Enum.reduce(0, fn {_, count}, acc -> count + acc end)

      unless dryrun? do
        Repo.transaction(
          fn ->
            Repo.delete_all(from(d in Download, where: d.day == ^date))

            @ets
            |> ets_stream()
            |> Stream.flat_map(fn {{organization, package, version}, count} ->
              organization_id = organizations[organization]
              package_id = packages[{organization_id, package}]

              if release_id = releases[{package_id, version}] do
                [%{release_id: release_id, downloads: count, day: date}]
              else
                []
              end
            end)
            |> Stream.chunk_every(1000, 1000, [])
            |> Enum.each(&Repo.insert_all(Download, &1))

            Repo.refresh_view(PackageDownload)
            Repo.refresh_view(ReleaseDownload)
          end,
          timeout: 60_000
        )
      end

      num
    after
      :ets.delete(@ets)
    end
  end

  defp ets_stream(ets) do
    start_fun = fn -> :ets.first(ets) end
    after_fun = fn _ -> :ok end

    next_fun = fn
      :"$end_of_table" -> {:halt, nil}
      key -> {:ets.lookup(ets, key), :ets.next(ets, key)}
    end

    Stream.resource(start_fun, next_fun, after_fun)
  end

  defp process_buckets(buckets, formats) do
    jobs =
      for b <- buckets,
          f <- formats,
          do: {b, f}

    Enum.each(jobs, fn {[bucket, region], {prefix, regex}} ->
      keys = Store.list(region, bucket, prefix) |> Enum.to_list()
      process_keys(region, bucket, regex, keys)
    end)
  end

  defp process_keys(region, bucket, regex, keys) do
    Task.async_stream(
      keys,
      fn key ->
        Store.get(region, bucket, key, [])
        |> maybe_unzip(key)
        |> process_file(regex)
      end,
      max_concurrency: 10,
      timeout: 600_000
    )
    |> Stream.run()
  end

  defp process_file(file, regex) do
    lines = String.split(file, "\n")

    Enum.each(lines, fn line ->
      case parse_line(line, regex) do
        {repository, package, version} ->
          key = {repository, package, version}
          :ets.update_counter(@ets, key, 1, {key, 0})

        nil ->
          :ok
      end
    end)
  end

  defp parse_line(line, regex) do
    case Regex.run(regex, line) do
      [_, repository, package, version, status] when status in ~w(200 304) ->
        {copy(nillify(repository)) || "hexpm", copy(package), copy(version)}

      _ ->
        nil
    end
  end

  defp organizations() do
    from(r in Organization, select: {r.name, r.id})
    |> Repo.all()
    |> Enum.into(%{})
  end

  defp packages() do
    from(p in Package, select: {{p.organization_id, p.name}, p.id})
    |> Repo.all()
    |> Enum.into(%{})
  end

  defp releases() do
    from(r in Release, select: {{r.package_id, r.version}, r.id})
    |> Repo.all()
    |> Enum.into(%{}, fn {{pid, vsn}, rid} -> {{pid, to_string(vsn)}, rid} end)
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
