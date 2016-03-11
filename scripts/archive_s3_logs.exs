[dir, date] = System.argv
File.mkdir_p!("logs/#{dir}")
File.cd!("logs")

buckets =
  case dir do
    "docs" ->
      [{"logs.hex.pm", "us-east-1"}]
    "hex" ->
      [{"logs.hex.pm",      "us-east-1"},
       {"logs-eu.hex.pm",   "eu-west-1"},
       {"logs-asia.hex.pm", "ap-southeast-1"}]
  end

Enum.each(buckets, fn {bucket, region} ->
  HexWeb.Utils.shell(~s(aws s3 cp s3://#{bucket} . --region #{region} --recursive --exclude "*" --include "#{dir}/#{date}*"))
end)

contents =
  Path.wildcard("**")
  |> Enum.reduce([], fn file, acc -> [acc|File.read!(file)] end)
  |> :zlib.gzip

filename = "#{dir}-#{date}.txt.gz"
File.write!(filename, contents)

HexWeb.Utils.shell(~s(aws s3 cp #{filename} s3://backup.hex.pm/log-archives/#{filename}))

Enum.each(buckets, fn {bucket, region} ->
  HexWeb.Utils.shell(~s(aws s3 rm s3://#{bucket} --region #{region} --recursive --exclude "*" --include "#{dir}/#{date}*"))
end)
