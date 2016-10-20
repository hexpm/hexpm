files = Path.wildcard("logs/hex/*")

log_regex_s3 = ~r"
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

# <134>2016-10-18T00:00:03Z cache-nrt6131 S3Logging[312468]: 52.192.248.204 "Tue, 18 Oct 2016 00:00:02 GMT" "GET /registry.ets.gz" 304 "Hex/0.13.2 (Elixir/1.3.2) (OTP/19.0)" (null)

log_regex_fastly = ~r"
  [^\040]+\040          # syslog header
  [^\040]+\040          # hostname
  [^\040]+\040          # other hostname?
  [^\040]+\040          # IP address
  \"[^\"]+\"\040        # timestamp
  (\"[^\"]+\")\040      # http request
  ([^\040]+)\040        # status
  (\"[^\"]+)\"\040      # user agent
  [^\040]+              # response size
"x

log_regex = log_regex_fastly
ua_regex = ~r"Hex/([^ ]+) \(Elixir/([^\)]+)\)"

uas =
  Enum.reduce(files, %{}, fn file, uas ->
    contents = File.read!(file)
    lines = String.split(contents, "\n", trim: true)
    Enum.reduce(lines, uas, fn line, uas ->
      case Regex.run(log_regex, line) do
        [_, request, status, ua] when status >= "200" and status < "400" ->
          if String.contains?(request, "registry.ets.gz") do
            case Regex.run(ua_regex, ua) do
              [_, _hex, elixir] ->
                Map.update(uas, elixir, 1, &(&1 + 1))
              nil ->
                uas
            end
          else
            uas
          end
        _ ->
          uas
      end
    end)
  end)

uas
|> Enum.sort_by(&elem(&1, 1), &>=/2)
|> Enum.each(fn {x, y} -> IO.puts "#{x} #{y}" end)
