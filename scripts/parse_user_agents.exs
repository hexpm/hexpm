files = Path.wildcard("logs/hex/*")

log_regex = ~r"
  [^\040]+\040          # bucket owner
  [^\040]+\040          # bucket
  \[.+\]\040            # time
  [^\040]+\040          # IP address
  [^\040]+\040          # requester ID
  [^\040]+\040          # request ID
  REST.GET.OBJECT\040
  registry.ets.gz\040
  \"[^\"]+\"\040        # request URI
  ([^\040]+)\040        # status
  [^\040]+\040          # error code
  [^\040]+\040          # bytes sent
  [^\040]+\040          # object size
  [^\040]+\040          # total time
  [^\040]+\040          # turn-around time
  \"[^\"]+\"\040        # referrer
  \"([^\"]+)\"\040      # user-agent
"x

ua_regex = ~r"Hex/([^ ]+) \(Elixir/([^\)]+)\)"

uas =
  Enum.reduce(files, %{}, fn file, uas ->
    contents = File.read!(file)
    lines = String.split(contents, "\n", trim: true)
    Enum.reduce(lines, uas, fn line, uas ->
      case Regex.run(log_regex, line) do
        [_, status, ua] when status >= "200" and status < "400" ->
          case Regex.run(ua_regex, ua) do
            [_, _hex, elixir] ->
              Map.update(uas, elixir, 1, &(&1 + 1))
            nil ->
              uas
          end
        [_, _, _] ->
          uas
        nil ->
          uas
      end
    end)
  end)

uas
|> Enum.sort_by(&elem(&1, 1), &>=/2)
|> Enum.each(fn {x, y} -> IO.puts "#{x} #{y}" end)

