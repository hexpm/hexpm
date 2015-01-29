defmodule HexWeb.Stats.Job do
  import Ecto.Query, only: [from: 2]
  require HexWeb.Repo
  alias HexWeb.Package
  alias HexWeb.Release
  alias HexWeb.Stats.Download

  @max_downloads_per_ip 10

  def run(date) do
    start()

    prefix = "hex/#{date_string(date)}"
    keys = Application.get_env(:hex_web, :store).list_logs(prefix)
    date = Ecto.Date.from_erl(date)

    # TODO: Map/Reduce
    dict = process_keys(keys) |> cap_on_ip
    packages = packages()
    releases = releases()

    HexWeb.Repo.transaction(fn ->
      HexWeb.Repo.delete_all(from(d in Download, where: d.day == ^date))

      Enum.each(dict, fn {{package, version}, count} ->
        pkg_id = packages[package]
        rel_id = releases[{pkg_id, version}]

        if rel_id do
          %Download{release_id: rel_id, downloads: count, day: date}
          |> HexWeb.Repo.insert
        end
      end)

      HexWeb.Stats.PackageDownload.refresh
      HexWeb.Stats.ReleaseDownload.refresh
    end)

    num = Enum.reduce(dict, 0, fn {_, count}, acc -> count + acc end)

    {:memory, memory} = :erlang.process_info(self, :memory)
    {memory, num}
  end

  defp start do
    HexWeb.Repo.start_link
  end

  defp process_keys(keys) do
    Enum.reduce(keys, HashDict.new, fn key, dict ->
      key
      |> Application.get_env(:hex_web, :store).get_logs
      |> process_file(dict)
    end)
  end

  defp cap_on_ip(dict) do
    Enum.reduce(dict, HashDict.new, fn {{release, _ip}, count}, dict ->
      count = min(@max_downloads_per_ip, count)
      Dict.update(dict, release, count, &(&1 + count))
    end)
  end

  defp process_file(file, dict) do
    lines = String.split(file, "\n")
    Enum.reduce(lines, dict, fn line, dict ->
      case parse_line(line) do
        {ip, package, version} ->
          key = {{package, version}, ip}
          Dict.update(dict, key, 1, &(&1 + 1))
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
    ([0-9\\.]+)           # version
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
    |> Enum.into(HashDict.new)
  end

  defp releases do
    from(r in Release, select: {{r.package_id, r.version}, r.id})
    |> HexWeb.Repo.all
    |> Enum.into(HashDict.new)
  end
end
