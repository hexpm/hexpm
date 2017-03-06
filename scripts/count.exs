defmodule Hexpm.Script.Count do
  @max_downloads_per_ip 10

  def run do
    {:ok, files} = :zip.unzip('2015-03.zip', [:memory])

    process_files(files)
    # |> cap_on_ip
    |> count_status
    |> Enum.sort(fn {_, x}, {_, y} -> sum(x) >= sum(y) end)
    |> Enum.take(100)
    |> Enum.each(&IO.inspect/1)
  end

  defp sum(map) do
    map |> Map.values |> Enum.sum
  end

  defp process_files(files) do
    Enum.reduce(files, %{}, fn {_, file}, dict ->
      process_file(file, dict)
    end)
  end

  defp cap_on_ip(dict) do
    Enum.reduce(dict, %{}, fn {{release, _ip}, count}, dict ->
      count = min(@max_downloads_per_ip, count)
      Map.update(dict, release, count, &(&1 + count))
    end)
  end

  defp count_status(dict) do
    Enum.reduce(dict, %{}, fn {{release, status}, count}, dict ->
      map = Map.put(%{}, status, count)
      Map.update(dict, release, map , &Map.put(&1, status, count))
    end)
  end

  defp process_file(file, dict) do
    lines = String.split(file, "\n")
    Enum.reduce(lines, dict, fn line, dict ->
      case parse_line(line) do
        {ip, package, version, status} ->
          status = String.to_integer(status)
          key = {{package, version}, status}
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
    ([0-9\\.]+)           # version
    .tar\040
    \"[^\"]+\"\040
    ([^\040]+)\040        # status code
    "Ux

  defp parse_line(line) do
    case Regex.run(@regex, line) do
      [_, ip, package, version, status] ->
        {ip, package, version, status}
      nil ->
        nil
    end
  end
end

Hexpm.Script.Count.run
