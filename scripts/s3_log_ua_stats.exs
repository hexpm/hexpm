date = List.first System.argv

defmodule HexWeb.Logs do
  def process_file(file, dict) do
    lines = String.split(file, "\n")
    Enum.reduce(lines, dict, fn line, dict ->
      case parse_line(line) do
        nil ->
          dict
        version ->
          Dict.update(dict, version, 1, &(&1 + 1))
      end
    end)
  end

  @regex ~r"
    \WREST.GET.OBJECT\W
    installs/(([^/]+)/)?hex.ez\W
    (.+)\W
    \"Mix/([^\"]+)\"
    "x

  defp parse_line(line) do
    case Regex.run(@regex, line) do
      nil -> nil
      list -> List.last(list)
    end
  end
end

files = Path.wildcard("logs/#{date}*")

dict = Enum.reduce(files, HashDict.new, fn file, dict ->
  binary = File.read!(file)
  HexWeb.Logs.process_file(binary, dict)
end)

sorted = Enum.sort(dict, fn left, right -> elem(left, 1) >= elem(right, 1) end)

Enum.each(sorted, fn {version, count} ->
  IO.puts "#{count}  #{version}"
end)
