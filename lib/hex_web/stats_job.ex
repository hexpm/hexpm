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
    [^\040]+\040        # request ID
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

    ips         = HexWeb.CDN.public_ips
    s3_dict     = process_buckets(buckets, s3_prefix, @s3_regex, ips)
    fastly_dict = process_buckets(buckets, fastly_prefix, @fastly_regex, ips)
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

  defp merge_dicts(s3, fastly) do
    Map.merge(s3, fastly, fn _, x, y -> x+y end)
  end

  defp process_buckets(buckets, prefix, regex, ips) do
    Enum.reduce(buckets, %{}, fn [bucket, region], dict ->
      keys = HexWeb.Store.list_logs(region, bucket, prefix)
      process_keys(region, bucket, regex, ips, keys, dict)
    end)
  end

  defp process_keys(region, bucket, regex, ips, keys, dict) do
    Enum.reduce(keys, dict, fn key, dict ->
      HexWeb.Store.get_logs(region, bucket, key)
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
