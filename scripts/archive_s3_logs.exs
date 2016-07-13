[action, dir, date] = System.argv
key_chunk_factor = 10_000
file_chunk_factor = 5 * 1024 * 1024

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

filename = "#{dir}-#{date}.txt.gz"
file = if action == "upload", do: File.open!(filename, [:write, :delayed_write, :compressed])

keys =
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

    IO.puts "Listing time: #{div(time, 1_000_000)}s"
    IO.puts "Keys: #{length keys}"

    if action == "upload" do
      IO.puts "Fetching objects (#{bucket})"
      {time, _} = :timer.tc(fn ->
        HexWeb.Store.S3.get_each(region, bucket, keys, fn _key, data ->
          IO.binwrite(file, data)
        end, timeout: :infinity)
      end)
      IO.puts "Fetching time: #{div(time, 1_000_000)}s"
    end

    {bucket, region, keys}
  end)

  IO.puts "Uploading archive (backup.hex.pm)"
  {time, _} = :timer.tc(fn ->
    key = "logs/monthly/#{filename}"

    upload_id = HexWeb.Store.S3.put_multipart_init("us-east-1", "backup.hex.pm", key, [])

    # NOTE: Could be parallel
    parts =
      File.stream!(filename, [], file_chunk_factor)
      |> Stream.with_index(1)
      |> Enum.map(fn {data, ix} ->
           etag = HexWeb.Store.S3.put_multipart_part("us-east-1", "backup.hex.pm", key, upload_id, ix, data)
           {ix, etag}
         end)

    HexWeb.Store.S3.put_multipart_complete("us-east-1", "backup.hex.pm", key, upload_id, parts)
  end)

  IO.puts "Uploading time: #{div(time, 1_000_000)}s"
end

if action == "delete" do
  keys = Enum.concat(keys)

  Enum.each(buckets, fn {bucket, region} ->
    IO.puts "Deleting keys (#{bucket})"
    {time, _} = :timer.tc(fn ->
      HexWeb.Store.S3.delete(region, bucket, keys, timeout: :infinity)
    end)
    IO.puts "Deleting time: #{div(time, 1_000_000)}s"
  end)
end
