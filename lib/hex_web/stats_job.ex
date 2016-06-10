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
    [^\040]+\040          # request ID
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
    "[^"]+"\040           # time
    "GET\040/tarballs/
    ([^-]+)               # package
    -
    ([\d\w\.\-]+)         # version
    .tar"\040
    ([0-9]{3})\040        # status
  >x

  def run(date, buckets, max_downloads_per_ip \\ 100, dryrun? \\ false) do
    start()

    s3_prefix     = "hex/#{date_string(date)}"
    fastly_prefix = "fastly_hex/#{date_string(date)}"
    {:ok, date}   = Ecto.Type.load(Ecto.Date, date)
    formats       = [{s3_prefix, @s3_regex}, {fastly_prefix, @fastly_regex}]

    ips = HexWeb.CDN.public_ips
    dict = process_buckets(buckets, formats, ips)
    dict = cap_on_ip(dict, max_downloads_per_ip)
    packages = packages()
    releases = releases()

    unless dryrun? do
      HexWeb.Repo.transaction(fn ->
        HexWeb.Repo.delete_all(from(d in Download, where: d.day == ^date))

        Enum.flat_map(dict, fn {{package, version}, count} ->
          pkg_id = packages[package]
          if rel_id = releases[{pkg_id, version}],
            do: [%{release_id: rel_id, downloads: count, day: date}],
          else: []
        end)
        |> Enum.chunk(1000, 1000, [])
        |> Enum.map(&HexWeb.Repo.insert_all(Download, &1))

        HexWeb.Repo.refresh_view(HexWeb.PackageDownload)
        HexWeb.Repo.refresh_view(HexWeb.ReleaseDownload)
      end)
    end

    num = Enum.reduce(dict, 0, fn {_, count}, acc -> count + acc end)

    {:memory, memory} = :erlang.process_info(self, :memory)
    {memory, num}
  end

  defp start do
    HexWeb.Repo.start_link
  end

  defp process_buckets(buckets, formats, ips) do
    jobs = for b <- buckets, f <- formats, do: {b, f}
    HexWeb.Utils.multi_task(jobs, fn {[bucket, region], {prefix, regex}} ->
      keys = HexWeb.Store.list(region, bucket, prefix) |> Enum.to_list
      process_keys(region, bucket, regex, ips, keys)
    end)
    |> Enum.reduce(%{}, &Map.merge(&1, &2, fn _, c1, c2 -> c1+c2 end))
  end

  defp process_keys(region, bucket, regex, ips, keys) do
    results = HexWeb.Store.get(region, bucket, keys)
              |> Enum.zip(keys)
    Enum.reduce(results, %{}, fn {content, key}, dict ->
      content
      |> maybe_unzip(key)
      |> process_file(regex, ips, dict)
    end)
  end

  defp cap_on_ip(dict, max_downloads_per_ip) do
    Enum.reduce(dict, %{}, fn
      {{release, "-"}, count}, dict ->
        Map.update(dict, release, count, &(&1 + count))
      {{release, _ip}, count}, dict ->
        count = min(max_downloads_per_ip, count)
        Map.update(dict, release, count, &(&1 + count))
    end)
  end

  defp process_file(file, regex, ips, dict) do
    lines = String.split(file, "\n")
    Enum.reduce(lines, dict, fn line, dict ->
      case parse_line(line, regex, ips) do
        {ip, package, version} ->
          key = {{package, version}, ip}
          Map.update(dict, key, 1, &(&1 + 1))
        nil ->
          dict
      end
    end)
  end

  defp parse_line(line, regex, ips) do
    case Regex.run(regex, line) do
      [_, ip, package, version, status] when status in ~w(200 304) ->
        unless in_ip_range?(ips, HexWeb.Utils.parse_ip(ip)) do
          {ip, package, version}
        end
      _ ->
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

  defp in_ip_range?(_range, nil),
    do: false
  defp in_ip_range?(list, ip) when is_list(list),
    do: Enum.any?(list, &in_ip_range?(&1, ip))
  defp in_ip_range?({range, mask}, ip),
    do: <<range::bitstring-size(mask)>> == <<ip::bitstring-size(mask)>>
end
