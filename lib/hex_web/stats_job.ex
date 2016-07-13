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

  @ets __MODULE__

  def run(date, buckets, max_downloads_per_ip \\ 100, dryrun? \\ false) do
    s3_prefix     = "hex/#{date_string(date)}"
    fastly_prefix = "fastly_hex/#{date_string(date)}"
    {:ok, date}   = Ecto.Type.load(Ecto.Date, date)
    formats       = [{s3_prefix, @s3_regex}, {fastly_prefix, @fastly_regex}]

    # No write_concurrency (issue ERL-188)
    :ets.new(@ets, [:named_table, :public])
    ips = HexWeb.CDN.public_ips
    process_buckets(buckets, formats, ips)
    cap_on_ip(max_downloads_per_ip)
    packages = packages()
    releases = releases()

    unless dryrun? do
      HexWeb.Repo.transaction(fn ->
        HexWeb.Repo.delete_all(from(d in Download, where: d.day == ^date))

        {acc, _num} = :ets.foldl(fn
          {{:cap, package, version}, count}, {acc, num} ->
            pkg_id = packages[package]
            {acc, num} =
              if rel_id = releases[{pkg_id, version}] do
                {[%{release_id: rel_id, downloads: count, day: date}|acc], num+1}
              else
                {acc, num}
              end

            if num >= 1000 do
              HexWeb.Repo.insert_all(Download, acc)
              {[], 0}
            else
              {acc, num}
            end
        end, {[], 0}, @ets)

        HexWeb.Repo.insert_all(Download, acc)

        HexWeb.Repo.refresh_view(HexWeb.PackageDownload)
        HexWeb.Repo.refresh_view(HexWeb.ReleaseDownload)
      end)
    end

    num = :ets.foldl(fn {_, count}, acc -> count + acc end, 0, @ets)

    {:memory, memory} = :erlang.process_info(self(), :memory)
    {memory, num}
  after
    :ets.delete(@ets)
  end

  defp process_buckets(buckets, formats, ips) do
    jobs = for b <- buckets, f <- formats, do: {b, f}
    Enum.each(jobs, fn {[bucket, region], {prefix, regex}} ->
      keys = HexWeb.Store.list(region, bucket, prefix) |> Enum.to_list
      process_keys(region, bucket, regex, ips, keys)
    end)
  end

  defp process_keys(region, bucket, regex, ips, keys) do
    HexWeb.Store.get_each(region, bucket, keys, fn key, content ->
      content
      |> maybe_unzip(key)
      |> process_file(regex, ips)
    end, [])
  end

  defp cap_on_ip(max_downloads_per_ip) do
    :ets.foldl(fn
      {{:ip, _package, _version, nil}, _count}, :ok ->
        :ok

      {{:ip, package, version, ip}, count}, :ok ->
        count = min(max_downloads_per_ip, count)
        key = {:cap, package, version}
        :ets.update_counter(@ets, key, count, {key, 0})
        :ets.delete(@ets, {:ip, package, version, ip})
        :ok

      {{:cap, _, _}, _}, :ok ->
        :ok
    end, :ok, @ets)
  end

  defp process_file(file, regex, ips) do
    lines = String.split(file, "\n")
    Enum.each(lines, fn line ->
      case parse_line(line, regex, ips) do
        {ip, package, version} ->
          key = {:ip, package, version, ip}
          :ets.update_counter(@ets, key, 1, {key, 0})
        nil ->
          :ok
      end
    end)
  end

  defp parse_line(line, regex, ips) do
    case Regex.run(regex, line) do
      [_, ip, package, version, status] when status in ~w(200 304) ->
        ip = parse_ip(ip)
        unless in_ip_range?(ips, ip) do
          {copy(ip), copy(package), copy(version)}
        end
      _ ->
        nil
    end
  end

  defp copy(nil), do: nil
  defp copy(binary), do: :binary.copy(binary)

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

  defp parse_ip("-"), do: nil
  defp parse_ip(ip), do: HexWeb.Utils.parse_ip(ip)

  defp in_ip_range?(_range, nil),
    do: false
  defp in_ip_range?(list, ip) when is_list(list),
    do: Enum.any?(list, &in_ip_range?(&1, ip))
  defp in_ip_range?({range, mask}, ip),
    do: <<range::bitstring-size(mask)>> == <<ip::bitstring-size(mask)>>
end
