[action, dir, date] = System.argv

buckets =
  case dir do
    "docs" ->
      [{"logs.hex.pm", "us-east-1"}]
    "hex" ->
      [{"logs.hex.pm",      "us-east-1"},
       {"logs-eu.hex.pm",   "eu-west-1"},
       {"logs-asia.hex.pm", "ap-southeast-1"}]
     "fastly_hex" ->
       [{"logs.hex.pm", "us-east-1"}]
  end

{keys, results} =
  Enum.map(buckets, fn {bucket, region} ->
    IO.puts "Listing keys (#{bucket})"
    {time, keys} = :timer.tc(fn ->
      HexWeb.Utils.multi_task(1..31, fn day ->
        day = day |> Integer.to_string |> String.pad_leading(2, "0")
        HexWeb.Store.S3.list(region, bucket, "#{dir}/#{date}-#{day}")
        |> Enum.to_list
      end)
      |> Enum.concat
    end)

    IO.puts "Listing time: #{div(time, 1000000)}s"
    IO.puts "Keys: #{length keys}"

    if action == "upload" do
      IO.puts "Fetching keys (#{bucket})"
      {time, results} = :timer.tc(fn ->
        HexWeb.Store.S3.get(region, bucket, keys, timeout: :infinity)
      end)
      IO.puts "Fetching time: #{div(time, 1000000)}s"

      {keys, results}
    else
      {keys, []}
    end
  end)
  |> Enum.unzip

if action == "upload" do
  contents = :zlib.gzip(results)
  filename = "#{dir}-#{date}.txt.gz"
  File.write!(filename, contents)

  IO.puts "Uploading archive (backup.hex.pm)"
  {time, _} = :timer.tc(fn ->
    HexWeb.Store.S3.put("us-east-1", "backup.hex.pm", "log-archives/#{filename}", contents, [])
  end)
  IO.puts "Uploading time: #{div(time, 1000000)}s"
end

if action == "delete" do
  keys = Enum.concat(keys)

  Enum.each(buckets, fn {bucket, region} ->
    IO.puts "Deleting keys (#{bucket})"
    {time, _} = :timer.tc(fn ->
      HexWeb.Store.S3.delete(region, bucket, keys, timeout: :infinity)
    end)
    IO.puts "Deleting time: #{div(time, 1000000)}s"
  end)
end
