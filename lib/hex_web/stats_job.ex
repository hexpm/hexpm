defmodule HexWeb.StatsJob do
  import Ecto.Query, only: [from: 2]
  require HexWeb.Repo
  alias HexWeb.Package
  alias HexWeb.Release
  alias HexWeb.Download

  @s3_regex ~r<
    [^\040]+\040          # bucket owner
    [^\040]+\040          # bucket
    \[.+\]\040            # time
    ([^\040]+)\040        # IP address
    [^\040]+\040          # requester ID
    ([^\040]+)\040        # request ID
    REST.GET.OBJECT\040
    tarballs/
    ([^-]+)               # package
    -
    ([\d\w\.\-]+)         # version
    .tar\040
    "[^"]+"\040           # request line
    ([0-9]{3})\040        # status
    >x

  @fastly_regex ~r<
    [^\040]+\040          # syslog
    [^\040]+\040          # user
    [^\040]+\040          # source
    ([^\040]+)\040        # IP address
    ([^\040]+)\040        # request ID
    "[^"]+"\040           # time
    "GET\040/tarballs/
    ([^-]+)               # package
    -
    ([\d\w\.\-]+)         # version
    .tar"\040
    ([0-9]{3})\040        # status
  >x

  def run(date, s3_buckets, fastly_bucket, max_downloads_per_ip \\ 100, dryrun? \\ false) do
    start()

    s3_prefix     = "hex/#{date_string(date)}"
    fastly_prefix = "fastly_hex/#{date_string(date)}"
    {:ok, date}   = Ecto.Type.load(Ecto.Date, date)

    s3_dict     = process_buckets(s3_buckets, s3_prefix, @s3_regex)
    fastly_dict = process_buckets([fastly_bucket], fastly_prefix, @fastly_regex)
    dict        = merge_dicts(s3_dict, fastly_dict)

    # TODO: Map/Reduce
    dict = cap_on_ip(dict, max_downloads_per_ip)
    packages = packages()
    releases = releases()

    unless dryrun? do
      HexWeb.Repo.transaction(fn ->
        HexWeb.Repo.delete_all(from(d in Download, where: d.day == ^date))

        Enum.each(dict, fn {{package, version}, count} ->
          pkg_id = packages[package]
          rel_id = releases[{pkg_id, version}]

          if rel_id do
            # TODO: This is inserting null ids with ecto 1.0, make sure this
            # is fixed 2.0 or use a changeset
            %Download{release_id: rel_id, downloads: count, day: date}
            |> HexWeb.Repo.insert!
          end
        end)

        HexWeb.PackageDownload.refresh
        HexWeb.ReleaseDownload.refresh
      end)
    end

    num = Enum.reduce(dict, 0, fn {_, count}, acc -> count + acc end)

    {:memory, memory} = :erlang.process_info(self, :memory)
    {memory, num}
  end

  defp start do
    HexWeb.Repo.start_link
  end

  # Do not count the same download in both S3 and Fastly.
  # We use S3's request id to uniquely identify requests, if the same
  # request ids are on S3 and Fastly we do not count the S3 request.
  # There can be multiple logged faslty requests for the same id because
  # fastly caches the S3 response.
  # Also note that this is check is not perfect since we fetch log files
  # for a whole day by filename and a request occuring at midnight can
  # be logged at different days for S3 and Fastly, but this number should
  # be really low.
  defp merge_dicts(s3, fastly) do
    dict = Map.merge(s3, fastly, fn _, _s3, fastly -> fastly end)
    Enum.reduce(dict, %{}, fn {_, list}, dict ->
      Enum.reduce(list, dict, fn {ip, package, version}, dict ->
        key = {{package, version}, ip}
        Map.update(dict, key, 1, &(&1 + 1))
      end)
    end)
  end

  defp process_buckets(buckets, prefix, regex) do
    Enum.reduce(buckets, %{}, fn
      [bucket, region], dict ->
        keys = HexWeb.Store.list_logs(region, bucket, prefix)
        process_keys(region, bucket, regex, keys, dict)
      bucket, dict ->
        keys = HexWeb.Store.list_logs(nil, bucket, prefix)
        process_keys(nil, bucket, regex, keys, dict)
    end)
  end

  defp process_keys(region, bucket, regex, keys, dict) do
    Enum.reduce(keys, dict, fn key, dict ->
      HexWeb.Store.get_logs(region, bucket, key)
      |> maybe_unzip(key)
      |> process_file(regex, dict)
    end)
  end

  defp cap_on_ip(dict, max_downloads_per_ip) do
    Enum.reduce(dict, %{}, fn {{release, _ip}, count}, dict ->
      count = min(max_downloads_per_ip, count)
      Map.update(dict, release, count, &(&1 + count))
    end)
  end

  defp process_file(file, regex, dict) do
    lines = String.split(file, "\n")
    Enum.reduce(lines, dict, fn line, dict ->
      case parse_line(line, regex) do
        {ip, request_id, package, version} ->
          tuple = {ip, package, version}
          Map.update(dict, request_id, [tuple], &[tuple|&1])
        nil ->
          dict
      end
    end)
  end

  defp parse_line(line, regex) do
    case Regex.run(regex, line) do
      [_, ip, request_id, package, version, status] when status in ~w(200 304) ->
        {ip, request_id, package, version}
      nil ->
        nil
    end
  end

  defp date_string(date) do
    list = Tuple.to_list(date)
    :io_lib.format("~4..0B-~2..0B-~2..0B", list)
    |> IO.iodata_to_binary
  end

  defp packages do
    from(p in Package, select: {p.name, p.id})
    |> HexWeb.Repo.all
    |> Enum.into(%{})
  end

  defp releases do
    from(r in Release, select: {{r.package_id, r.version}, r.id})
    |> HexWeb.Repo.all
    |> Enum.into(%{}, fn {{pid, vsn}, rid} -> {{pid, to_string(vsn)}, rid} end)
  end

  defp maybe_unzip(data, key) do
    if String.ends_with?(key, ".gz"),
      do: :zlib.gunzip(data),
    else: data
  end
end
