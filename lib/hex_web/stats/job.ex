defmodule HexWeb.Stats.Job do
  import Ecto.Query, only: [from: 2]
  require HexWeb.Repo
  alias HexWeb.Package
  alias HexWeb.Release
  alias HexWeb.Stats.Download

  def run(date, buckets, max_downloads_per_ip \\ 100, dryrun? \\ false) do
    start()

    store       = Application.get_env(:hex_web, :store)
    prefix      = "hex/#{date_string(date)}"
    {:ok, date} = Ecto.Type.load(Ecto.Date, date)

    dict =
      Enum.reduce(buckets, %{}, fn [bucket, region], dict ->
        keys = store.list_logs(region, bucket, prefix)
        process_keys(store, region, bucket, keys, dict)
      end)

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
            %Download{release_id: rel_id, downloads: count, day: date}
            |> HexWeb.Repo.insert!
          end
        end)

        HexWeb.Stats.PackageDownload.refresh
        HexWeb.Stats.ReleaseDownload.refresh
      end)
    end

    num = Enum.reduce(dict, 0, fn {_, count}, acc -> count + acc end)

    {:memory, memory} = :erlang.process_info(self, :memory)
    {memory, num}
  end

  defp start do
    HexWeb.Repo.start_link
  end

  defp process_keys(store, region, bucket, keys, dict) do
    Enum.reduce(keys, dict, fn key, dict ->
      store.get_logs(region, bucket, key)
      |> process_file(dict)
    end)
  end

  defp cap_on_ip(dict, max_downloads_per_ip) do
    Enum.reduce(dict, %{}, fn {{release, _ip}, count}, dict ->
      count = min(max_downloads_per_ip, count)
      Map.update(dict, release, count, &(&1 + count))
    end)
  end

  defp process_file(file, dict) do
    lines = String.split(file, "\n")
    Enum.reduce(lines, dict, fn line, dict ->
      case parse_line(line) do
        {ip, package, version} ->
          key = {{package, version}, ip}
          Map.update(dict, key, 1, &(&1 + 1))
        nil ->
          dict
      end
    end)
  end

  @regex ~r"
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
    "x

  defp parse_line(line) do
    case Regex.run(@regex, line) do
      [_, ip, package, version] ->
        {ip, package, version}
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
end
