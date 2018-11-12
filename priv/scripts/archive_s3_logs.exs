[action, date] = System.argv()

buckets = [{"logs.hex.pm", "us-east-1"}]
dir = "fastly_hex"
tmp = Application.get_env(:hexpm, :tmp_dir)
filename = Path.join([tmp, "logs", "#{dir}-#{date}.txt.gz"])

File.mkdir_p!(Path.dirname(filename))

uncompress = fn data, key ->
  if String.ends_with?(key, ".gz") do
    :zlib.gunzip(data)
  else
    data
  end
end

keys =
  buckets
  |> Enum.flat_map(fn {bucket, region} ->
    for day <- 1..31, do: {bucket, region, day}
  end)
  |> Stream.map(fn {bucket, region, day} ->
    day = day |> Integer.to_string() |> String.pad_leading(2, "0")
    prefix = "#{dir}/#{date}-#{day}"
    {bucket, region, Hexpm.Store.S3.list(region, bucket, prefix)}
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
  File.open!(filename, [:write, :delayed_write, :compressed], fn file ->
    keys
    |> Task.async_stream(
      fn {bucket, region, stream} ->
        {bucket, region, Enum.to_list(stream)}
      end,
      max_concurrency: 5,
      ordered: false,
      timeout: 600_000
    )
    |> Stream.flat_map(fn {:ok, {bucket, region, keys}} ->
      for key <- keys, do: {bucket, region, key}
    end)
    |> Task.async_stream(
      fn {bucket, region, key} ->
        data =
          Hexpm.Store.S3.get(region, bucket, key, [])
          |> uncompress.(key)

        IO.binwrite(file, data)
      end,
      max_concurrency: 20,
      ordered: false,
      timeout: 60_000
    )
    |> Stream.run()
  end)
end

if action == "upload" || action == "fetch-and-upload" do
  key = "logs/monthly/#{filename}"

  ExAws.S3.Upload.stream_file(filename, [:read_ahead])
  |> ExAws.S3.upload("backup.hex.pm", key, timeout: 600_000)
  |> ExAws.request!(region: "us-east-1")
end

if action == "delete" do
  Enum.each(keys, fn {bucket, region, keys} ->
    Hexpm.Store.S3.delete_many(region, bucket, keys)
  end)
end
