defmodule Mix.Tasks.Hexpm.Stats do
  use Mix.Task
  require Logger
  import Ecto.Query, only: [from: 2]
  alias Hexpm.{CDN, Repo, Store, Utils}

  alias Hexpm.Repository.{
    Download,
    Package,
    PackageDownload,
    Release,
    ReleaseDownload,
    Repository
  }

  @shortdoc "Calculates yesterdays download stats"

  @s3_regex ~r<
    [^\040]+\040 # bucket owner
    [^\040]+\040 # bucket
    \[.+\]\040 # time
    ([^\040]+)\040 # IP address
    [^\040]+\040 # requester ID
    [^\040]+\040 # request ID
    REST.GET.OBJECT\040
    () # no repository
    tarballs/
    ([^-]+) # package
    -
    ([\d\w\.\-]+) # version
    .tar(?:\?[^\040"]*)?\040
    "[^"]+"\040 # request line
    ([0-9]{3})\040 # status
    >x

  @fastly_regex ~r<
    [^\040]+\040 # syslog
    [^\040]+\040 # user
    [^\040]+\040 # source
    ([^\040]+)\040 # IP address
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

  def run(_args) do
    Mix.Task.run("app.start")

    buckets = Application.get_env(:hexpm, :logs_buckets)

    try do
      {time, {memory, size}} =
        :timer.tc(fn ->
          run(Utils.utc_yesterday(), buckets)
        end)

      Logger.warn(
        "STATS_JOB_COMPLETED #{size} downloads (#{div(time, 1000)}ms, #{div(memory, 1024)}kb)"
      )
    catch
      exception ->
        stacktrace = System.stacktrace()
        Logger.error("STATS_JOB_FAILED")

        System.at_exit(fn
          0 -> System.halt(1)
          _ -> :ok
        end)

        reraise exception, stacktrace
    end
  end

  @doc false
  def run(date, buckets, max_downloads_per_ip \\ 1000, dryrun? \\ false) do
    s3_prefix = "hex/#{date}"
    fastly_prefix = "fastly_hex/#{date}"
    formats = [{s3_prefix, @s3_regex}, {fastly_prefix, @fastly_regex}]
    ips = CDN.public_ips()

    :ets.new(@ets, [:named_table, :public, write_concurrency: true])

    map =
      try do
        process_buckets(buckets, formats, ips)
        cap_on_ip(max_downloads_per_ip)
      after
        :ets.delete(@ets)
      end

    repositories = repositories()
    packages = packages()
    releases = releases()

    # May not be a perfect count since it counts downloads without a release
    # in the database. Should be uncommon
    num = Enum.reduce(map, 0, fn {_, count}, acc -> count + acc end)

    unless dryrun? do
      Repo.transaction(fn ->
        Repo.delete_all(from(d in Download, where: d.day == ^date))

        Enum.flat_map(map, fn {{repository, package, version}, count} ->
          repository_id = repositories[repository || "hexpm"]
          package_id = packages[{repository_id, package}]

          if release_id = releases[{package_id, version}] do
            [%{release_id: release_id, downloads: count, day: date}]
          else
            []
          end
        end)
        |> Enum.chunk_every(1000, 1000, [])
        |> Enum.each(&Repo.insert_all(Download, &1))

        Repo.refresh_view(PackageDownload)
        Repo.refresh_view(ReleaseDownload)
      end)
    end

    {:memory, memory} = :erlang.process_info(self(), :memory)
    {memory, num}
  end

  defp process_buckets(buckets, formats, ips) do
    jobs =
      for b <- buckets,
          f <- formats,
          do: {b, f}

    Enum.each(jobs, fn {[bucket, region], {prefix, regex}} ->
      keys = Store.list(region, bucket, prefix) |> Enum.to_list()
      process_keys(region, bucket, regex, ips, keys)
    end)
  end

  defp process_keys(region, bucket, regex, ips, keys) do
    Task.async_stream(
      keys,
      fn key ->
        Store.get(region, bucket, key, [])
        |> maybe_unzip(key)
        |> process_file(regex, ips)
      end,
      max_concurrency: 10,
      timeout: 600_000
    )
    |> Stream.run()
  end

  defp cap_on_ip(max_downloads_per_ip) do
    :ets.foldl(
      fn
        {{_repository, _package, _version, nil}, _count}, map ->
          map

        {{repository, package, version, _ip}, count}, map ->
          count = min(max_downloads_per_ip, count)
          Map.update(map, {repository, package, version}, count, &(&1 + count))
      end,
      %{},
      @ets
    )
  end

  defp process_file(file, regex, ips) do
    lines = String.split(file, "\n")

    Enum.each(lines, fn line ->
      case parse_line(line, regex, ips) do
        {ip, repository, package, version} ->
          key = {repository, package, version, ip}
          :ets.update_counter(@ets, key, 1, {key, 0})

        nil ->
          :ok
      end
    end)
  end

  defp parse_line(line, regex, ips) do
    case Regex.run(regex, line) do
      [_, ip, repository, package, version, status] when status in ~w(200 304) ->
        ip = parse_ip(ip)

        unless Utils.in_ip_range?(ips, ip) do
          {copy(ip), copy(nillify(repository)), copy(package), copy(version)}
        end

      _ ->
        nil
    end
  end

  defp repositories() do
    from(r in Repository, select: {r.name, r.id})
    |> Repo.all()
    |> Enum.into(%{})
  end

  defp packages() do
    from(p in Package, select: {{p.repository_id, p.name}, p.id})
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

  defp parse_ip("-"), do: nil
  defp parse_ip(ip), do: Utils.parse_ip(ip)
end
