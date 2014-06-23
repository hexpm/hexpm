defmodule HexWeb.Stats.Job do
  import Ecto.Query, only: [from: 2]
  require HexWeb.Repo
  alias HexWeb.Package
  alias HexWeb.Release
  alias HexWeb.Stats.Download

  def run(date) do
    start()

    prefix = "logs/#{date_string(date)}"
    keys = HexWeb.Config.store.list(prefix)
    date = Ecto.Date.from_erl(date)

    # TODO: Map/Reduce
    dict = process_keys(keys)
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
      |> HexWeb.Config.store.get
      |> process_file(dict)
    end)
  end

  defp process_file(file, dict) do
    lines = String.split(file, "\n")
    Enum.reduce(lines, dict, fn line, dict ->
      case parse_line(line) do
        {_, _} = release ->
          Dict.update(dict, release, 1, &(&1 + 1))
        nil ->
          dict
      end
    end)
  end

  @regex ~r"
    \WREST.GET.OBJECT\W
    tarballs/
    ([^-]+)           # package
    -
    ([0-9\\.]+)         # version
    .tar\W
    "x

  defp parse_line(line) do
    case Regex.run(@regex, line) do
      [_, package, version] -> {package, version}
      nil                   -> nil
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
