[action, date] = System.argv()

buckets = ["gcs,hexpm-logs-prod"]
dir = "fastly_hex"
tmp = Application.get_env(:hexpm, :tmp_dir)
filename = "#{dir}-#{date}.txt.gz"
filepath = Path.join([tmp, "logs", "#{dir}-#{date}.txt.gz"])

File.mkdir_p!(Path.dirname(filepath))

uncompress = fn data, key ->
  if String.ends_with?(key, ".gz") do
    :zlib.gunzip(data)
  else
    data
  end
end

keys =
  buckets
  |> Enum.flat_map(fn bucket ->
    for day <- 1..31, do: {bucket, day}
  end)
  |> Stream.map(fn {bucket, day} ->
    day = day |> Integer.to_string() |> String.pad_leading(2, "0")
    prefix = "#{dir}/#{date}-#{day}"
    {bucket, Hexpm.Store.list(bucket, prefix)}
  end)

if action == "count" do
  keys
  |> Task.async_stream(
    fn {_bucket, _region, stream} ->
      Enum.count(stream)
    end,
    max_concurrency: 10,
    ordered: false,
    timeout: 600_000
  )
  |> Stream.map(fn {:ok, count} -> count end)
  |> Enum.sum()
  |> IO.inspect()
end

if action == "fetch" || action == "fetch-and-upload" do
  File.open!(filepath, [:write, :delayed_write, :compressed], fn file ->
    Enum.each(keys, fn {bucket, stream} ->
      Task.async_stream(
        stream,
        fn key ->
          data =
            Hexpm.Store.get(bucket, key, [])
            |> uncompress.(key)

          IO.binwrite(file, data)
        end,
        max_concurrency: 20,
        ordered: false,
        timeout: 60_000
      )
      |> Stream.run()
    end)
  end)
end

if action == "upload" || action == "fetch-and-upload" do
  key = "logs/monthly/#{filename}"

  ExAws.S3.Upload.stream_file(filepath, [:read_ahead])
  |> ExAws.S3.upload("backup.hex.pm", key, timeout: 600_000)
  |> ExAws.request!(region: "us-east-1")

  File.rm!(filepath)
end

if action == "delete" do
  Enum.each(keys, fn {bucket, keys} ->
    Hexpm.Store.delete_many(bucket, keys)
  end)
end
